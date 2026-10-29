"""Convert a locally obtained PMX character with Blender and MMD Tools.

Run through Blender's background Python runner. The source package and all
generated character artifacts remain local and must not be redistributed.
"""

import argparse
import importlib.util
import json
import math
from pathlib import Path
import sys
from zipfile import ZipFile

import bpy
from mathutils import Vector


def arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--addon", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--working", required=True, type=Path)
    parser.add_argument("--turn-around", action="store_true")
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1:])


def enable_importer(directory, working):
    dependencies = working / "python-wheels"
    dependencies.mkdir(exist_ok=True)
    for wheel in (directory / "wheels").glob("*.whl"):
        with ZipFile(wheel) as archive:
            for item in archive.infolist():
                destination = (dependencies / item.filename).resolve()
                if not destination.is_relative_to(dependencies.resolve()):
                    raise RuntimeError("Unsafe dependency archive path.")
            archive.extractall(dependencies)
    sys.path.insert(0, str(dependencies))
    spec = importlib.util.spec_from_file_location(
        "mmd_tools", directory / "__init__.py", submodule_search_locations=[str(directory)]
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules["mmd_tools"] = module
    spec.loader.exec_module(module)
    module.register()
    return module


def prepare_materials(directory):
    """Use portable preview-surface materials; MMD shaders are not USD shaders."""
    texture_directory = directory / "textures"
    texture_directory.mkdir(exist_ok=True)
    materials = []
    images = {}
    for index, material in enumerate(bpy.data.materials):
        material.use_nodes = True
        base = material.node_tree.nodes.get("mmd_base_tex")
        image = base.image if base and base.type == "TEX_IMAGE" else None
        color = tuple(material.mmd_material.diffuse_color)
        alpha = material.mmd_material.alpha
        record = {"index": index, "source": material.name, "alpha": alpha}
        material.name = f"CharacterMaterial_{index:02d}"
        if image:
            if not image.has_data:
                image.reload()
                if len(image.pixels):
                    _ = image.pixels[0]
            if not image.has_data:
                raise RuntimeError(f"Missing texture data: {image.filepath}")
            if image.name not in images:
                destination = texture_directory / f"texture_{len(images):02d}.png"
                images[image.name] = str(destination)
                image.filepath_raw = str(destination)
                image.file_format = "PNG"
                image.save()
            record["texture"] = images[image.name]
        nodes = material.node_tree.nodes
        nodes.clear()
        output = nodes.new("ShaderNodeOutputMaterial")
        surface = nodes.new("ShaderNodeBsdfPrincipled")
        surface.inputs["Base Color"].default_value = (*color, 1)
        surface.inputs["Roughness"].default_value = 0.85
        surface.inputs["Specular IOR Level"].default_value = 0.15
        surface.inputs["Alpha"].default_value = alpha
        material.node_tree.links.new(surface.outputs["BSDF"], output.inputs["Surface"])
        if image:
            texture = nodes.new("ShaderNodeTexImage")
            texture.image = image
            material.node_tree.links.new(texture.outputs["Color"], surface.inputs["Base Color"])
            if image.channels == 4 and alpha > 0.99:
                material.node_tree.links.new(texture.outputs["Alpha"], surface.inputs["Alpha"])
        material.surface_render_method = "DITHERED"
        material.use_backface_culling = False
        materials.append(record)
    return materials


def mesh_bounds(meshes):
    points = [obj.matrix_world @ Vector(point) for obj in meshes for point in obj.bound_box]
    low = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
    high = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
    return low, high


def export_model(output):
    properties = bpy.ops.wm.usd_export.get_rna_type().properties.keys()
    settings = {
        "filepath": str(output),
        "selected_objects_only": True,
        "export_animation": False,
        "export_armatures": True,
        "export_shapekeys": True,
        "export_materials": True,
        "export_textures": True,
        "generate_preview_surface": True,
        "overwrite_textures": True,
        "relative_paths": True,
        "convert_orientation": True,
        "export_global_forward_selection": "NEGATIVE_Z",
        "export_global_up_selection": "Y",
    }
    if "convert_orientation" not in properties:
        raise RuntimeError("This Blender exporter cannot explicitly convert the asset to Y up.")
    supported = {key: value for key, value in settings.items() if key in properties}
    print("USD export settings:", supported, flush=True)
    result = bpy.ops.wm.usd_export(**supported)
    if "FINISHED" not in result or not output.exists():
        raise RuntimeError("USDZ export did not produce an output file.")


def preview(directory):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.render.resolution_x = 768
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    if scene.world is None:
        scene.world = bpy.data.worlds.new("PreviewWorld")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.08, 0.08, 0.08, 1)
    scene.view_settings.view_transform = "Standard"
    bpy.ops.object.camera_add(location=(0, 3.4, 0.92))
    camera = bpy.context.object
    camera.rotation_euler = (Vector((0, 0, 0.83)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 1.95
    scene.camera = camera
    for position, energy, size in [((2, 3, 4), 220, 4), ((-3, 1, 2), 150, 3), ((0, -2, 3), 180, 2)]:
        bpy.ops.object.light_add(type="AREA", location=position)
        light = bpy.context.object
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.rotation_euler = (Vector((0, 0, 0.9)) - light.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(directory / "preview.png")
    bpy.ops.render.render(write_still=True)


def main():
    args = arguments()
    args.working.mkdir(parents=True, exist_ok=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    enable_importer(args.addon.resolve(), args.working)
    result = bpy.ops.mmd_tools.import_model(
        filepath=str(args.source.resolve()),
        types={"MESH", "ARMATURE", "MORPHS"},
        scale=0.08,
        clean_model=True,
        remove_doubles=False,
        rename_bones=False,
        save_log=False,
        log_level="WARNING",
    )
    if "FINISHED" not in result:
        raise RuntimeError("PMX import failed.")
    imported = list(bpy.context.scene.objects)
    meshes = [obj for obj in imported if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError("Source contains no mesh objects.")
    materials = prepare_materials(args.working)
    root = bpy.data.objects.new("Columbina", None)
    bpy.context.scene.collection.objects.link(root)
    for obj in imported:
        if obj.parent is None:
            obj.parent = root
    for index, obj in enumerate(imported):
        obj.name = f"Character_{obj.type}_{index:03d}"
    if args.turn_around:
        root.rotation_euler.z = math.pi
    bpy.context.view_layer.update()
    low, high = mesh_bounds(meshes)
    source_height = high.z - low.z
    if not math.isfinite(source_height) or source_height <= 0:
        raise RuntimeError("Source has invalid physical bounds.")
    factor = 1.6 / source_height
    root.scale = (factor, factor, factor)
    bpy.context.view_layer.update()
    low, high = mesh_bounds(meshes)
    root.location = (-(low.x + high.x) / 2, -(low.y + high.y) / 2, -low.z)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [root, *imported]:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    export_model(args.output.resolve())
    report = {
        "blender": bpy.app.version_string,
        "meshes": len(meshes),
        "vertices": sum(len(obj.data.vertices) for obj in meshes),
        "triangles": sum(sum(len(face.vertices) - 2 for face in obj.data.polygons) for obj in meshes),
        "materials": materials,
        "armatures": sum(obj.type == "ARMATURE" for obj in imported),
        "shapeKeys": sum(len(obj.data.shape_keys.key_blocks) - 1 for obj in meshes if obj.data.shape_keys),
        "outputBytes": args.output.stat().st_size,
        "staticPreview": True,
    }
    (args.working / "conversion-report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    bpy.ops.wm.save_as_mainfile(filepath=str(args.working / "Columbina.blend"))
    preview(args.working)
    print("PASS: character converted and authoring preview rendered.", flush=True)


if __name__ == "__main__":
    main()
