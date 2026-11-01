"""Exercise USD composition and face removal with small synthetic character data."""

import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdSkel, UsdUtils, Vt

spec = importlib.util.spec_from_file_location('footwear', Path(__file__).resolve().parents[1] / 'prepare-columbina-footwear.py')
footwear = importlib.util.module_from_spec(spec)
spec.loader.exec_module(footwear)


class FootwearPreparationTests(unittest.TestCase):
    def fixture(self, directory, *, invalid_subset=False, indexed_uv=False):
        authored = directory / 'source.usdc'
        stage = Usd.Stage.CreateNew(str(authored))
        stage.SetDefaultPrim(stage.DefinePrim('/root'))
        mesh = UsdGeom.Mesh.Define(stage, '/root/Body')
        mesh.CreatePointsAttr(Vt.Vec3fArray([(0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1)]))
        mesh.CreateFaceVertexCountsAttr(Vt.IntArray([3, 3, 3, 3]))
        mesh.CreateFaceVertexIndicesAttr(Vt.IntArray([0, 1, 2, 0, 1, 3, 1, 2, 3, 0, 2, 3]))
        mesh.CreateNormalsAttr(Vt.Vec3fArray([(0, 0, 1)] * 12))
        mesh.SetNormalsInterpolation(UsdGeom.Tokens.faceVarying)
        uv = UsdGeom.PrimvarsAPI(mesh).CreatePrimvar('st', Sdf.ValueTypeNames.TexCoord2fArray, UsdGeom.Tokens.faceVarying)
        uv.Set(Vt.Vec2fArray([(i, i) for i in range(12)]))
        if indexed_uv:
            uv.SetIndices(Vt.IntArray(range(12)))
        for name, indices in [('CharacterMaterial_00', [0, 3]), ('CharacterMaterial_19', [1, 9] if invalid_subset else [1, 2])]:
            material = UsdShade.Material.Define(stage, '/root/Materials/' + name)
            subset = UsdGeom.Subset.Define(stage, '/root/Body/' + name)
            subset.CreateFamilyNameAttr('materialBind')
            subset.CreateElementTypeAttr('face')
            subset.CreateIndicesAttr(Vt.IntArray(indices))
            UsdShade.MaterialBindingAPI.Apply(subset.GetPrim()).Bind(material)
        skeleton = UsdSkel.Skeleton.Define(stage, '/root/Skeleton')
        skeleton.CreateJointsAttr(Vt.TokenArray(['Root']))
        skeleton.CreateBindTransformsAttr(Vt.Matrix4dArray([Gf.Matrix4d(1)]))
        skeleton.CreateRestTransformsAttr(Vt.Matrix4dArray([Gf.Matrix4d(1)]))
        binding = UsdSkel.BindingAPI.Apply(mesh.GetPrim())
        binding.CreateSkeletonRel().SetTargets([skeleton.GetPath()])
        binding.CreateJointIndicesPrimvar(False, 1).Set(Vt.IntArray([0] * 4))
        binding.CreateJointWeightsPrimvar(False, 1).Set(Vt.FloatArray([1] * 4))
        shape = UsdSkel.BlendShape.Define(stage, '/root/Body/Blink')
        shape.CreatePointIndicesAttr(Vt.IntArray([2]))
        shape.CreateOffsetsAttr(Vt.Vec3fArray([(0, -0.1, 0)]))
        binding.CreateBlendShapesAttr(Vt.TokenArray(['Blink']))
        binding.CreateBlendShapeTargetsRel().SetTargets([shape.GetPath()])
        stage.GetRootLayer().Save()
        source = directory / 'Columbina.usdz'
        self.assertTrue(UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(authored)), str(source)))
        return source

    def test_native_layer_removes_only_heel_faces_and_preserves_source(self):
        with tempfile.TemporaryDirectory() as working:
            directory = Path(working)
            source = self.fixture(directory)
            before = source.read_bytes()
            output = directory / 'ColumbinaBarefoot.usdc'
            footwear.prepare(source, output)
            result = Usd.Stage.Open(str(output))
            mesh = UsdGeom.Mesh(result.GetPrimAtPath('/root/Body'))
            self.assertEqual(list(mesh.GetFaceVertexIndicesAttr().Get()), [0, 1, 2, 0, 2, 3])
            self.assertEqual(list(mesh.GetNormalsAttr().Get()), [Gf.Vec3f(0, 0, 1)] * 6)
            self.assertEqual(list(UsdGeom.PrimvarsAPI(mesh).GetPrimvar('st').Get()),
                             [Gf.Vec2f(i, i) for i in [0, 1, 2, 9, 10, 11]])
            heel = UsdGeom.Subset(result.GetPrimAtPath('/root/Body/CharacterMaterial_19'))
            self.assertEqual(list(heel.GetIndicesAttr().Get()), [])
            self.assertTrue(UsdShade.MaterialBindingAPI(heel.GetPrim()).ComputeBoundMaterial()[0])
            self.assertEqual(UsdSkel.Skeleton(result.GetPrimAtPath('/root/Skeleton')).GetJointsAttr().Get(),
                             Vt.TokenArray(['Root']))
            self.assertEqual(UsdSkel.BlendShape(result.GetPrimAtPath('/root/Body/Blink')).GetPointIndicesAttr().Get(),
                             Vt.IntArray([2]))
            self.assertEqual(source.read_bytes(), before)
            self.assertEqual(footwear.digest(source), hashlib.sha256(before).hexdigest())
            self.assertTrue((directory / 'ColumbinaFootwear.json').is_file())

    def test_invalid_heel_faces_cannot_produce_a_variant(self):
        with tempfile.TemporaryDirectory() as working:
            directory = Path(working)
            source = self.fixture(directory, invalid_subset=True)
            output = directory / 'ColumbinaBarefoot.usdc'
            with self.assertRaisesRegex(RuntimeError, 'invalid source face'):
                footwear.prepare(source, output)
            self.assertFalse(output.exists())
            self.assertFalse((directory / 'ColumbinaFootwear.json').exists())

    def test_unsupported_indexed_face_data_is_rejected(self):
        with tempfile.TemporaryDirectory() as working:
            directory = Path(working)
            source = self.fixture(directory, indexed_uv=True)
            output = directory / 'ColumbinaBarefoot.usdc'
            with self.assertRaisesRegex(RuntimeError, 'Indexed face attributes'):
                footwear.prepare(source, output)
            self.assertFalse(output.exists())
            self.assertFalse((directory / 'ColumbinaFootwear.json').exists())


if __name__ == '__main__':
    unittest.main(argv=[__file__], verbosity=2)
