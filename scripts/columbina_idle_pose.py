"""Build a reversible, asset-specific standing pose in Blender.

The exported deltas use evaluated parent-local joints so authoring constraints
are accounted for before RealityKit applies the pose to its imported baseline.
"""

import importlib.util
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector


_ARM_LOWERING_DEGREES = 26.0
_THUMB_ADDUCTION_DEGREES = 6.0
_IDENTITY_TOLERANCE = 1e-6
_FOOT_MOTION_TOLERANCE = 1e-5


def _evaluated_local_matrices(armature):
    evaluated = armature.evaluated_get(bpy.context.evaluated_depsgraph_get())
    return {
        bone.name: bone.parent.matrix.inverted() @ bone.matrix
        if bone.parent else bone.matrix.copy()
        for bone in evaluated.pose.bones
    }


def _mesh_vertices(armature):
    """Capture world-space positions for meshes deformed by this armature."""
    graph = bpy.context.evaluated_depsgraph_get()
    vertices = []
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH" or not any(
            modifier.type == "ARMATURE" and modifier.object == armature
            for modifier in obj.modifiers
        ):
            continue
        evaluated = obj.evaluated_get(graph)
        vertices.extend(evaluated.matrix_world @ vertex.co for vertex in evaluated.data.vertices)
    if not vertices:
        raise RuntimeError("The standing-pose source has no armature-deformed mesh.")
    return vertices


def _rotate_armature_axis(armature, bone_name, axis, degrees):
    bone = armature.pose.bones[bone_name]
    current = bone.matrix.copy()
    rotation = Quaternion(Vector(axis), math.radians(degrees))
    bone.matrix = (
        Matrix.Translation(current.translation)
        @ rotation.to_matrix().to_4x4()
        @ current.to_3x3().to_4x4()
    )
    bpy.context.view_layer.update()


def _column_major(matrix):
    return [float(matrix[row][column]) for column in range(4) for row in range(4)]


def _cuff_checker():
    path = Path(__file__).with_name("columbina_cuff_clearance.py")
    spec = importlib.util.spec_from_file_location("columbina_cuff_clearance", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.evaluate_cuff_clearance


def _adduct_thumb(armature, runtime_names, prefix):
    evaluated = armature.evaluated_get(bpy.context.evaluated_depsgraph_get())
    base = evaluated.pose.bones[runtime_names[prefix + "親指０"]].matrix.translation.copy()
    tip = evaluated.pose.bones[runtime_names[prefix + "親指先"]].matrix.translation.copy()
    index = evaluated.pose.bones[runtime_names[prefix + "人指１"]].matrix.translation.copy()
    axis = (tip - base).cross(index - base)
    if axis.length < 1e-8:
        raise RuntimeError("Cannot determine the thumb's anatomical adduction axis.")
    _rotate_armature_axis(armature, runtime_names[prefix + "親指０"], axis.normalized(), _THUMB_ADDUCTION_DEGREES)


def build_idle_pose(armature, source_names):
    """Return pose metadata without changing the armature's source pose.

    ``source_names`` maps the final ASCII bone leaf names to original source
    names. Runtime composition is ``importedBaselineMatrix * jointDelta``;
    every flat matrix in ``jointDeltas`` contains 16 column-major elements.
    """
    runtime_names = {source: runtime for runtime, source in source_names.items()}
    controls = {
        "leftArm": "左腕",
        "rightArm": "右腕",
        "leftThumb": "左親指０",
        "rightThumb": "右親指０",
    }
    motion_sources = {
        "spine": "上半身",
        "chest": "上半身2",
        "neck": "首",
        "head": "頭",
    }
    fixed_sources = ["左足首", "右足首", "左つま先", "右つま先"]
    thumb_landmarks = {prefix + source for prefix in ("左", "右") for source in ("親指先", "人指１")}
    required = set(controls.values()) | set(motion_sources.values()) | set(fixed_sources) | thumb_landmarks
    missing = sorted(required - runtime_names.keys())
    if missing:
        raise RuntimeError(f"The standing-pose source is missing required bones: {missing}")
    if set(source_names) != {bone.name for bone in armature.data.bones}:
        raise RuntimeError("The source-name mapping does not match the exported armature.")

    bases = {bone.name: bone.matrix_basis.copy() for bone in armature.pose.bones}
    bpy.context.view_layer.update()
    reference = _evaluated_local_matrices(armature)
    before_vertices = _mesh_vertices(armature)
    minimum_z = min(point.z for point in before_vertices)
    maximum_z = max(point.z for point in before_vertices)
    foot_limit = minimum_z + (maximum_z - minimum_z) * 0.15
    foot_indices = [index for index, point in enumerate(before_vertices) if point.z <= foot_limit]
    check_cuffs = _cuff_checker()
    reference_cuffs = check_cuffs(armature, source_names)

    try:
        # The cuff does not follow elbow flexion enough to clear the hand.
        # Keep elbows extended and gently adduct each thumb toward its palm.
        # These axes are in the source armature's Z-up authoring coordinates.
        _rotate_armature_axis(armature, runtime_names[controls["leftArm"]], (0, 1, 0), _ARM_LOWERING_DEGREES)
        _rotate_armature_axis(armature, runtime_names[controls["rightArm"]], (0, 1, 0), -_ARM_LOWERING_DEGREES)
        _adduct_thumb(armature, runtime_names, "左")
        _adduct_thumb(armature, runtime_names, "右")
        relaxed = _evaluated_local_matrices(armature)
        after_vertices = _mesh_vertices(armature)
        if len(before_vertices) != len(after_vertices):
            raise RuntimeError("The standing-pose evaluation changed mesh topology.")
        foot_motion = max(
            (before_vertices[index] - after_vertices[index]).length for index in foot_indices
        )
        if foot_motion > _FOOT_MOTION_TOLERANCE:
            raise RuntimeError(f"The standing pose moves lower-body vertices by {foot_motion:.6f} meters.")
        natural_cuffs = check_cuffs(armature, source_names)
        if any(record["crossingTrianglePairs"] for record in natural_cuffs.values()):
            raise RuntimeError(f"The natural pose intersects the main cuff surfaces: {natural_cuffs}")

        deltas = {}
        for name, before in reference.items():
            delta = before.inverted() @ relaxed[name]
            if any(
                abs(delta[row][column] - (1.0 if row == column else 0.0)) > _IDENTITY_TOLERANCE
                for row in range(4) for column in range(4)
            ):
                deltas[name] = _column_major(delta)

        return {
            "schemaVersion": 1,
            "jointDeltas": deltas,
            "motionJoints": {
                semantic: runtime_names[source] for semantic, source in motion_sources.items()
            },
            "fixedJoints": [runtime_names[source] for source in fixed_sources],
            "authoring": {
                "armLoweringDegrees": _ARM_LOWERING_DEGREES,
                "elbowForwardDegrees": 0.0,
                "thumbAdductionDegrees": _THUMB_ADDUCTION_DEGREES,
                "coordinateSpace": "Evaluated parent-local deltas; column-major matrices.",
                "controlledJoints": {
                    semantic: runtime_names[source] for semantic, source in controls.items()
                },
                "checkedLowerBodyVertices": len(foot_indices),
                "maximumLowerBodyVertexMotionMeters": foot_motion,
                "cuffClearance": {
                    "scope": "Hand surfaces against the main sleeve material; strict segment/triangle crossings.",
                    "reference": reference_cuffs,
                    "natural": natural_cuffs,
                },
            },
        }
    finally:
        # Export the reference mesh and rig; the application owns pose selection.
        for name, basis in bases.items():
            armature.pose.bones[name].matrix_basis = basis
        bpy.context.view_layer.update()
