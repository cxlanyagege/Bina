"""Check visible hand surfaces against the selected model's main cuff mesh.

This is an authoring regression check for one known asset, not a general cloth
collision solver. Strict segment/triangle crossings exclude coincident edge
endpoints so the result measures penetration rather than shared boundaries.
"""

import bpy
from mathutils.bvhtree import BVHTree
from mathutils.geometry import intersect_ray_tri


_HAND_MATERIALS = {"CharacterMaterial_00", "CharacterMaterial_14", "CharacterMaterial_15"}
_CUFF_MATERIAL = "CharacterMaterial_16"
_CUFF_RADIUS_METERS = 0.2
_SEGMENT_ENDPOINT_TOLERANCE = 1e-6


def _edges_cross_triangle(first, second):
    for index in range(3):
        start = first[index]
        direction = first[(index + 1) % 3] - start
        length = direction.length
        if length <= 2 * _SEGMENT_ENDPOINT_TOLERANCE:
            continue
        direction.normalize()
        hit = intersect_ray_tri(*second, direction, start, True)
        if hit is None:
            continue
        distance = (hit - start).dot(direction)
        if _SEGMENT_ENDPOINT_TOLERANCE < distance < length - _SEGMENT_ENDPOINT_TOLERANCE:
            return True
    return False


def evaluate_cuff_clearance(armature, source_names):
    """Return hand/cuff crossings for both sides of the evaluated pose."""
    runtime_names = {source: runtime for runtime, source in source_names.items()}
    graph = bpy.context.evaluated_depsgraph_get()
    evaluated_armature = armature.evaluated_get(graph)
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH" and any(
        modifier.type == "ARMATURE" and modifier.object == armature for modifier in obj.modifiers
    )]
    result = {}
    for side, source_wrist in [("left", "左手首"), ("right", "右手首")]:
        wrist_name = runtime_names[source_wrist]
        hand_bones = {bone.name for bone in armature.data.bones if bone.name == wrist_name
                      or any(parent.name == wrist_name for parent in bone.parent_recursive)}
        wrist = armature.matrix_world @ evaluated_armature.pose.bones[wrist_name].matrix.translation
        crossing_pairs = 0
        crossed_hand_polygons = set()
        crossed_cuff_polygons = set()
        hand_triangle_count = 0
        cuff_triangle_count = 0
        sampled_distances = []
        for mesh_index, obj in enumerate(meshes):
            evaluated = obj.evaluated_get(graph)
            vertices = [evaluated.matrix_world @ vertex.co for vertex in evaluated.data.vertices]
            if len(vertices) != len(obj.data.vertices):
                raise RuntimeError("Cuff validation requires unchanged evaluated mesh topology.")
            hand_vertices = {vertex.index for vertex in obj.data.vertices if any(
                obj.vertex_groups[group.group].name in hand_bones and group.weight > 0.05
                for group in vertex.groups
            )}
            obj.data.calc_loop_triangles()
            hand = []
            cuff = []
            for triangle in obj.data.loop_triangles:
                material = obj.data.materials[triangle.material_index].name
                indices = tuple(triangle.vertices)
                record = (indices, triangle.polygon_index)
                if material in _HAND_MATERIALS and any(index in hand_vertices for index in indices):
                    hand.append(record)
                elif material == _CUFF_MATERIAL and min(
                    (vertices[index] - wrist).length for index in indices
                ) < _CUFF_RADIUS_METERS:
                    cuff.append(record)
            if not hand or not cuff:
                continue
            hand_triangle_count += len(hand)
            cuff_triangle_count += len(cuff)
            hand_tree = BVHTree.FromPolygons(vertices, [indices for indices, _ in hand], all_triangles=True)
            cuff_tree = BVHTree.FromPolygons(vertices, [indices for indices, _ in cuff], all_triangles=True)
            for hand_index, cuff_index in hand_tree.overlap(cuff_tree):
                first = [vertices[index] for index in hand[hand_index][0]]
                second = [vertices[index] for index in cuff[cuff_index][0]]
                if _edges_cross_triangle(first, second) or _edges_cross_triangle(second, first):
                    crossing_pairs += 1
                    crossed_hand_polygons.add((mesh_index, hand[hand_index][1]))
                    crossed_cuff_polygons.add((mesh_index, cuff[cuff_index][1]))
            for index in {index for indices, _ in hand for index in indices}:
                nearest = cuff_tree.find_nearest(vertices[index])
                if nearest[0] is not None:
                    sampled_distances.append(nearest[3])
        if not hand_triangle_count or not cuff_triangle_count or not sampled_distances:
            raise RuntimeError(f"No complete {side} hand/cuff surfaces were available for validation.")
        result[side] = {
            "handTriangleCount": hand_triangle_count,
            "cuffTriangleCount": cuff_triangle_count,
            "crossingTrianglePairs": crossing_pairs,
            "crossingHandPolygons": len(crossed_hand_polygons),
            "crossingCuffPolygons": len(crossed_cuff_polygons),
            "minimumSampledHandVertexDistanceMeters": min(sampled_distances),
        }
    return result
