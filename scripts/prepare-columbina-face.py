"""Repair facial targets from a retained Blender file without re-exporting the character.

Run with Blender's Python runner and --disable-autoexec. Source models, repaired
USDZ files, metadata, and reports remain local under the character-use boundary.
"""

import argparse
import hashlib
import json
from pathlib import Path
import sys
from zipfile import ZipFile

import bpy
import numpy as np
from pxr import Gf, Sdf, Usd, UsdGeom, UsdSkel, UsdUtils, Vt


def arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument('--authoring', required=True, type=Path)
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    return parser.parse_args(sys.argv[sys.argv.index('--') + 1:])


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def invariant_data(stage):
    """Capture the delivered geometry, skinning, and skeleton that this tool must preserve."""
    result = {}
    for prim in stage.Traverse():
        if prim.IsA(UsdSkel.BlendShape):
            continue
        values = {}
        for attribute in prim.GetAttributes():
            if attribute.GetName() in ('skel:blendShapes', 'blendShapes', 'blendShapeWeights'):
                continue
            value = attribute.Get()
            if value is None:
                continue
            if isinstance(value, (Vt.Vec3fArray, Vt.FloatArray, Vt.IntArray)):
                values[attribute.GetName()] = hashlib.sha256(np.asarray(value).tobytes()).hexdigest()
            else:
                values[attribute.GetName()] = repr(value)
        result[str(prim.GetPath())] = values
    return result


def main():
    args = arguments()
    if args.input.resolve() == args.output.resolve():
        raise RuntimeError('Generate and validate a separate candidate before replacing the delivered model.')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    working = args.output.parent / 'face-package'
    working.mkdir(exist_ok=True)
    with ZipFile(args.input) as archive:
        for name in archive.namelist():
            if Path(name).is_absolute() or '..' in Path(name).parts:
                raise RuntimeError('Unsafe USDZ archive path.')
        archive.extractall(working)
        root_name = archive.namelist()[0]
        texture_hashes = {name: hashlib.sha256(archive.read(name)).hexdigest()
                          for name in archive.namelist() if name.startswith('textures/')}

    bpy.ops.wm.open_mainfile(filepath=str(args.authoring.resolve()))
    mesh = next(obj for obj in bpy.context.scene.objects if obj.type == 'MESH')
    if not mesh.data.shape_keys:
        raise RuntimeError('The retained authoring mesh has no shape keys.')
    keys = list(mesh.data.shape_keys.key_blocks)[1:]
    stage = Usd.Stage.Open(str(working / root_name))
    before = invariant_data(stage)
    usd_meshes = [UsdGeom.Mesh(prim) for prim in stage.Traverse() if prim.IsA(UsdGeom.Mesh)]
    if len(usd_meshes) != 1:
        raise RuntimeError('Expected exactly one delivered mesh.')
    usd_mesh = usd_meshes[0]
    basis = np.array([tuple(point.co) for point in mesh.data.shape_keys.reference_key.data], dtype=np.float32)
    delivered = np.asarray(usd_mesh.GetPointsAttr().Get())
    if basis.shape != delivered.shape or np.max(np.abs(basis - delivered)) > 1e-7:
        raise RuntimeError('Authoring points do not match the exact delivered vertex order and coordinates.')
    for prim in list(stage.Traverse()):
        if prim.IsA(UsdSkel.BlendShape):
            stage.RemovePrim(prim.GetPath())

    names, targets, inventory = [], [], []
    for index, key in enumerate(keys):
        name = f'Face_{index:04d}'
        offsets = np.array([tuple(point.co) for point in key.data], dtype=np.float32) - basis
        indices = np.flatnonzero(np.any(np.abs(offsets) > 1e-8, axis=1))
        path = usd_mesh.GetPath().AppendChild(name)
        shape = UsdSkel.BlendShape.Define(stage, path)
        shape.CreatePointIndicesAttr(Vt.IntArray(indices.tolist()))
        shape.CreateOffsetsAttr(Vt.Vec3fArray([Gf.Vec3f(*map(float, offsets[i])) for i in indices]))
        names.append(name)
        targets.append(path)
        inventory.append({'name': name, 'sourceName': key.name, 'affectedVertices': len(indices)})
    binding = UsdSkel.BindingAPI.Apply(usd_mesh.GetPrim())
    binding.CreateBlendShapesAttr(Vt.TokenArray(names))
    binding.CreateBlendShapeTargetsRel().SetTargets(targets)
    for prim in stage.Traverse():
        if prim.IsA(UsdSkel.Animation):
            animation = UsdSkel.Animation(prim)
            if animation.GetBlendShapesAttr().Get():
                animation.CreateBlendShapesAttr(Vt.TokenArray(names))
                animation.CreateBlendShapeWeightsAttr(Vt.FloatArray([0.0] * len(names)))
    if invariant_data(stage) != before:
        raise RuntimeError('Facial repair changed non-facial geometry, skinning, skeleton, or material data.')
    stage.GetRootLayer().Save()
    if not UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str((working / root_name).resolve())), str(args.output.resolve())):
        raise RuntimeError('Could not package the facial candidate.')
    with ZipFile(args.output) as archive:
        for name, expected in texture_hashes.items():
            if hashlib.sha256(archive.read(name)).hexdigest() != expected:
                raise RuntimeError(f'Texture bytes changed: {name}')
    source_to_name = {item['sourceName']: item['name'] for item in inventory}
    required = {'blink': 'まばたき', 'smile': 'にやり', 'browSmile': 'にこり',
                'browRaise': '上', 'mouthOpen': 'あ', 'mouthRound': 'お'}
    profile = {'schemaVersion': 1, 'modelSHA256': digest(args.output),
               'channels': {semantic: source_to_name[source] for semantic, source in required.items()},
               'coveringMaterial': 'CharacterMaterial_12'}
    (args.output.parent / 'ColumbinaFace.json').write_text(json.dumps(profile, indent=2) + '\n')
    for name in ['ColumbinaIdlePose.json', 'ColumbinaPhysics.json']:
        paired = json.loads((args.input.parent / name).read_text())
        if paired['modelSHA256'] != digest(args.input):
            raise RuntimeError(f'The input metadata is not paired: {name}')
        paired['modelSHA256'] = profile['modelSHA256']
        (args.output.parent / name).write_text(json.dumps(paired, indent=2) + '\n')
    report = {'sourceModelSHA256': digest(args.input), 'candidateModelSHA256': profile['modelSHA256'],
              'shapeCount': len(keys), 'inventory': inventory, 'textureHashes': texture_hashes,
              'nonFacialDataUnchanged': True, 'basisMaximumError': float(np.max(np.abs(basis - delivered)))}
    (args.output.parent / 'face-preparation-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print('PASS:', len(keys), 'unique facial targets; geometry, skeleton, skinning and textures preserved.', flush=True)


if __name__ == '__main__':
    main()
