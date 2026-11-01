"""Author a native-importable barefoot layer without rebuilding RealityKit meshes.

Run with Blender's background Python runner and --disable-autoexec. The binary
USD layer references its sibling original USDZ; textures, skinning, and facial
targets remain in that unchanged package. Generated character data stays local.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

import numpy as np
from pxr import Usd, UsdGeom, UsdShade, Vt


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_preserved(source, candidate, changed):
    """Reject any change outside the explicit face removal and corner remapping."""
    if [p.GetPath() for p in source.Traverse()] != [p.GetPath() for p in candidate.Traverse()]:
        raise RuntimeError('Footwear preparation changed the scene hierarchy.')
    for prim in source.Traverse():
        other = candidate.GetPrimAtPath(prim.GetPath())
        if prim.GetTypeName() != other.GetTypeName():
            raise RuntimeError(f'Prim type changed: {prim.GetPath()}')
        for attribute in prim.GetAttributes():
            if str(attribute.GetPath()) not in changed and attribute.Get() != other.GetAttribute(attribute.GetName()).Get():
                raise RuntimeError(f'Unrelated attribute changed: {attribute.GetPath()}')
        for relation in prim.GetRelationships():
            if relation.GetTargets() != other.GetRelationship(relation.GetName()).GetTargets():
                raise RuntimeError(f'Relationship changed: {relation.GetPath()}')


def prepare(source_path, output):
    if source_path.parent != output.parent or source_path == output:
        raise RuntimeError('The original USDZ and distinct output layer must be siblings.')
    source_hash = digest(source_path)
    source = Usd.Stage.Open(str(source_path))
    meshes = [UsdGeom.Mesh(p) for p in source.Traverse() if p.IsA(UsdGeom.Mesh)]
    if len(meshes) != 1 or not source.GetDefaultPrim():
        raise RuntimeError('Expected one source mesh and a default prim.')
    mesh = meshes[0]
    subsets = [UsdGeom.Subset(p) for p in mesh.GetPrim().GetChildren() if p.IsA(UsdGeom.Subset)]
    heels = [s for s in subsets if UsdShade.MaterialBindingAPI(s.GetPrim()).ComputeBoundMaterial()[0].GetPrim().GetName()
             == 'CharacterMaterial_19']
    if len(heels) != 1:
        raise RuntimeError('The water-heel material subset is missing or ambiguous.')
    counts = np.asarray(mesh.GetFaceVertexCountsAttr().Get())
    indices = np.asarray(mesh.GetFaceVertexIndicesAttr().Get())
    removed = set(heels[0].GetIndicesAttr().Get())
    if not removed or not np.all(counts == 3) or len(indices) != int(counts.sum()):
        raise RuntimeError('Expected valid triangulated source geometry and nonempty heels.')
    if min(removed) < 0 or max(removed) >= len(counts):
        raise RuntimeError('Heel subset refers to an invalid source face.')
    if sorted(i for s in subsets for i in s.GetIndicesAttr().Get()) != list(range(len(counts))):
        raise RuntimeError('Material subsets must partition the source faces exactly once.')
    keep = np.array([i not in removed for i in range(len(counts))])
    corners = np.repeat(keep, counts)
    remap = np.cumsum(keep) - 1

    # A sibling staging file keeps the relative USDZ reference valid during validation.
    handle, name = tempfile.mkstemp(prefix='.footwear-', suffix='.usdc', dir=output.parent)
    os.close(handle)
    staged = Path(name)
    staged.unlink()
    try:
        target = Usd.Stage.CreateNew(str(staged))
        root = target.DefinePrim(source.GetDefaultPrim().GetPath())
        root.GetReferences().AddReference(source_path.name)
        target.SetDefaultPrim(root)
        UsdGeom.SetStageUpAxis(target, UsdGeom.GetStageUpAxis(source))
        UsdGeom.SetStageMetersPerUnit(target, UsdGeom.GetStageMetersPerUnit(source))
        bare = UsdGeom.Mesh(target.GetPrimAtPath(mesh.GetPath()))
        changed = set()

        def replace(attribute, value):
            bare.GetPrim().GetAttribute(attribute.GetName()).Set(value)
            changed.add(str(attribute.GetPath()))

        replace(mesh.GetFaceVertexCountsAttr(), Vt.IntArray(counts[keep].tolist()))
        replace(mesh.GetFaceVertexIndicesAttr(), Vt.IntArray(indices[corners].tolist()))
        for attribute in mesh.GetPrim().GetAttributes():
            if attribute.GetNumTimeSamples():
                raise RuntimeError('Animated mesh attributes require a separate authoring policy.')
            interpolation = attribute.GetMetadata('interpolation')
            if interpolation not in ('faceVarying', 'uniform') or not attribute.HasAuthoredValueOpinion():
                continue
            if mesh.GetPrim().HasAttribute(attribute.GetName() + ':indices'):
                raise RuntimeError(f'Indexed face attributes require explicit remapping: {attribute.GetName()}')
            value = attribute.Get()
            mask = corners if interpolation == 'faceVarying' else keep
            if value is None or len(value) != len(mask):
                raise RuntimeError(f'Unexpected face attribute size: {attribute.GetName()}')
            replace(attribute, type(value)(np.asarray(value)[mask].tolist()))
        for subset in subsets:
            attribute = UsdGeom.Subset(target.GetPrimAtPath(subset.GetPath())).GetIndicesAttr()
            attribute.Set(Vt.IntArray([int(remap[i]) for i in subset.GetIndicesAttr().Get() if i not in removed]))
            changed.add(str(attribute.GetPath()))
        # Keep the empty heel subset and its binding: native import retains material slots.
        target.GetRootLayer().Save()
        verify_preserved(source, target, changed)
        if len(bare.GetFaceVertexCountsAttr().Get()) != len(counts) - len(removed):
            raise RuntimeError('Incorrect barefoot face count.')
        if digest(source_path) != source_hash:
            raise RuntimeError('The original package changed during preparation.')
        profile = {'schemaVersion': 1, 'modelSHA256': source_hash, 'barefootSHA256': digest(staged)}
        staged.replace(output)
        manifest = output.with_name('ColumbinaFootwear.json')
        manifest.write_text(json.dumps(profile, indent=2) + '\n')
        print(f'PASS: removed {len(removed)} heel triangles; retained {len(counts) - len(removed)} triangles; '
              f'unchanged skeleton, skinning, points, facial targets, materials, and textures; '
              f'{output.stat().st_size} byte layer.', flush=True)
    finally:
        staged.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    if args.input.suffix != '.usdz' or args.output.name != 'ColumbinaBarefoot.usdc':
        raise RuntimeError('Expected the original USDZ and ColumbinaBarefoot.usdc output.')
    prepare(args.input.resolve(), args.output.resolve())


if __name__ == '__main__':
    main()
