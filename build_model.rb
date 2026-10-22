module MCPBuildingBuilder
  M = 39.37007874

  module_function

  def material(model, name, rgb, alpha = 1.0)
    mat = model.materials.add(name)
    mat.color = Sketchup::Color.new(*rgb)
    mat.alpha = alpha
    mat
  end

  def add_box(entities, name, x, y, z, dx, dy, dz, mat)
    return nil if dx.abs < 0.001 || dy.abs < 0.001 || dz.abs < 0.001

    group = entities.add_group
    group.name = name
    points = [
      Geom::Point3d.new(x * M, y * M, z * M),
      Geom::Point3d.new((x + dx) * M, y * M, z * M),
      Geom::Point3d.new((x + dx) * M, (y + dy) * M, z * M),
      Geom::Point3d.new(x * M, (y + dy) * M, z * M)
    ]
    face = group.entities.add_face(points)
    face.reverse! if face.normal.z < 0
    face.pushpull(dz * M)
    group.material = mat
    group
  end

  def add_face_box(entities, name, axis, plane, sign, u, z, width, height, depth, mat)
    if axis == :y
      y = sign < 0 ? plane - depth : plane
      add_box(entities, name, u, y, z, width, depth, height, mat)
    else
      x = sign < 0 ? plane - depth : plane
      add_box(entities, name, x, u, z, depth, width, height, mat)
    end
  end

  def add_window(entities, prefix, axis, plane, sign, u, z, width, height, transoms, mats)
    frame_depth = 0.16
    frame_width = 0.10
    glass = mats[:glass]
    frame = mats[:frame]
    stone = mats[:stone]

    add_face_box(entities, "#{prefix} Glass", axis, plane, sign,
                 u + 0.03, z + 0.03, width - 0.06, height - 0.06, 0.055, glass)
    add_face_box(entities, "#{prefix} Frame Bottom", axis, plane, sign,
                 u - 0.06, z - 0.06, width + 0.12, frame_width, frame_depth, frame)
    add_face_box(entities, "#{prefix} Frame Top", axis, plane, sign,
                 u - 0.06, z + height - 0.04, width + 0.12, frame_width, frame_depth, frame)
    add_face_box(entities, "#{prefix} Frame Left", axis, plane, sign,
                 u - 0.06, z, frame_width, height, frame_depth, frame)
    add_face_box(entities, "#{prefix} Frame Right", axis, plane, sign,
                 u + width - 0.04, z, frame_width, height, frame_depth, frame)
    add_face_box(entities, "#{prefix} Mullion", axis, plane, sign,
                 u + width * 0.5 - 0.035, z + frame_width,
                 0.07, height - frame_width * 2, frame_depth, frame)

    transoms.each do |fraction|
      add_face_box(entities, "#{prefix} Transom", axis, plane, sign,
                   u + frame_width, z + height * fraction - 0.035,
                   width - frame_width * 2, 0.07, frame_depth, frame)
    end

    add_face_box(entities, "#{prefix} Sill", axis, plane, sign,
                 u - 0.15, z - 0.16, width + 0.30, 0.10, 0.22, stone)
  end

  def build
    model = Sketchup.active_model

    model.start_operation("Create building from elevations", true)
    begin
      model.entities.grep(Sketchup::Group)
                  .select { |group| group.name == "BUILDING_FROM_ELEVATIONS" }
                  .each(&:erase!)
      model.materials.to_a.select { |mat| mat.name.start_with?("MCP") }.each do |mat|
        model.materials.remove(mat) if mat.valid?
      end

      mats = {
        brick: material(model, "MCP Brick Rust", [112, 61, 47]),
        brick_dark: material(model, "MCP Brick Shadow", [82, 43, 34]),
        glass: material(model, "MCP Glass Blue Gray", [87, 111, 120], 0.80),
        frame: material(model, "MCP Window Frame", [35, 38, 39]),
        stone: material(model, "MCP Stone Trim", [205, 204, 197]),
        roof: material(model, "MCP Roof Gray", [69, 70, 69]),
        canopy: material(model, "MCP Canopy Metal", [48, 50, 51]),
        sign: material(model, "MCP Sign Panel", [219, 211, 193])
      }

      root = model.entities.add_group
      root.name = "BUILDING_FROM_ELEVATIONS"

      massing = root.entities.add_group
      massing.name = "01_MAIN_MASSING"
      add_box(massing.entities, "Main brick volume", 0, 0, 0, 60, 30, 12.2, mats[:brick])
      add_box(massing.entities, "Base course south", -0.10, -0.12, 0, 60.20, 0.16, 0.38, mats[:brick_dark])
      add_box(massing.entities, "Base course north", -0.10, 29.96, 0, 60.20, 0.16, 0.38, mats[:brick_dark])
      add_box(massing.entities, "Base course east", 59.96, -0.10, 0, 0.16, 30.20, 0.38, mats[:brick_dark])
      add_box(massing.entities, "Base course west", -0.12, -0.10, 0, 0.16, 30.20, 0.38, mats[:brick_dark])

      add_box(massing.entities, "Roof slab", -0.35, -0.35, 12.20, 60.70, 30.70, 0.32, mats[:roof])
      add_box(massing.entities, "Parapet south", -0.35, -0.35, 12.52, 60.70, 0.35, 1.45, mats[:brick])
      add_box(massing.entities, "Parapet north", -0.35, 30.00, 12.52, 60.70, 0.35, 1.45, mats[:brick])
      add_box(massing.entities, "Parapet west", -0.35, 0.00, 12.52, 0.35, 30.00, 1.45, mats[:brick])
      add_box(massing.entities, "Parapet east", 60.00, 0.00, 12.52, 0.35, 30.00, 1.45, mats[:brick])
      add_box(massing.entities, "Parapet cap south", -0.48, -0.48, 13.97, 60.96, 0.58, 0.12, mats[:stone])
      add_box(massing.entities, "Parapet cap north", -0.48, 29.90, 13.97, 60.96, 0.58, 0.12, mats[:stone])
      add_box(massing.entities, "Parapet cap west", -0.48, -0.10, 13.97, 0.58, 30.20, 0.12, mats[:stone])
      add_box(massing.entities, "Parapet cap east", 59.90, -0.10, 13.97, 0.58, 30.20, 0.12, mats[:stone])

      add_box(massing.entities, "Belt south", -0.12, -0.18, 8.03, 60.24, 0.24, 0.24, mats[:stone])
      add_box(massing.entities, "Belt north", -0.12, 29.94, 8.03, 60.24, 0.24, 0.24, mats[:stone])
      add_box(massing.entities, "Belt east", 59.94, -0.12, 8.03, 0.24, 30.24, 0.24, mats[:stone])
      add_box(massing.entities, "Belt west", -0.18, -0.12, 8.03, 0.24, 30.24, 0.24, mats[:stone])
      add_box(massing.entities, "Belt upper south", -0.12, -0.13, 4.32, 60.24, 0.18, 0.15, mats[:stone])
      add_box(massing.entities, "Belt upper north", -0.12, 29.95, 4.32, 60.24, 0.18, 0.15, mats[:stone])

      annex = root.entities.add_group
      annex.name = "02_WEST_ANNEX"
      add_box(annex.entities, "Annex volume", -12.0, 0.0, 0, 12.0, 12.0, 4.25, mats[:brick])
      add_box(annex.entities, "Annex roof", -12.3, -0.3, 4.25, 12.6, 12.6, 0.30, mats[:roof])
      add_box(annex.entities, "Annex parapet west", -12.30, -0.30, 4.55, 0.35, 12.60, 0.75, mats[:brick])
      add_box(annex.entities, "Annex parapet south", -12.30, -0.30, 4.55, 12.60, 0.35, 0.75, mats[:brick])
      add_box(annex.entities, "Annex parapet north", -12.30, 11.95, 4.55, 12.60, 0.35, 0.75, mats[:brick])
      add_box(annex.entities, "Annex cap", -12.44, -0.44, 5.28, 12.88, 12.88, 0.10, mats[:stone])

      entry = root.entities.add_group
      entry.name = "03_ENTRY_PAVILION"
      add_box(entry.entities, "Entry brick volume", 60.0, 0.0, 0, 5.2, 10.0, 4.25, mats[:brick])
      add_box(entry.entities, "Entry roof slab", 59.6, -0.45, 4.25, 6.0, 10.9, 0.28, mats[:roof])
      add_box(entry.entities, "Entrance canopy", 58.6, -1.10, 4.05, 7.3, 11.8, 0.22, mats[:canopy])
      add_box(entry.entities, "Canopy fascia", 58.6, -1.10, 3.82, 7.3, 0.14, 0.23, mats[:frame])

      roof_group = root.entities.add_group
      roof_group.name = "04_ROOF_PENTHOUSES"
      add_box(roof_group.entities, "Roof room west", 10.0, 22.0, 12.52, 11.0, 6.8, 2.25, mats[:brick])
      add_box(roof_group.entities, "Roof room west cap", 9.65, 21.65, 14.77, 11.7, 7.5, 0.22, mats[:roof])
      add_box(roof_group.entities, "Roof room east", 44.0, 21.5, 12.52, 11.0, 7.0, 2.25, mats[:brick])
      add_box(roof_group.entities, "Roof room east cap", 43.65, 21.15, 14.77, 11.7, 7.7, 0.22, mats[:roof])

      upper_centers = [5.0, 13.0, 21.0, 29.0, 37.0, 45.0, 53.0]
      south = root.entities.add_group
      south.name = "05_SOUTH_FACADE"
      north = root.entities.add_group
      north.name = "06_NORTH_FACADE"
      upper_centers.each_with_index do |cx, i|
        [5.00, 8.90].each_with_index do |z, level|
          add_window(south.entities, "South B#{i + 1} L#{level + 1}",
                     :y, 0, -1, cx - 1.65, z, 3.30, 2.72, [0.52], mats)
          add_window(north.entities, "North B#{i + 1} L#{level + 1}",
                     :y, 30, 1, cx - 1.65, z, 3.30, 2.72, [0.52], mats)
        end
        add_window(south.entities, "South Ground B#{i + 1}",
                   :y, 0, -1, cx - 1.10, 0.72, 2.20, 2.55, [0.58], mats)
        add_window(north.entities, "North Ground B#{i + 1}",
                   :y, 30, 1, cx - 1.10, 0.72, 2.20, 2.55, [0.58], mats)
      end

      end_centers = [4.4, 9.7, 15.0, 20.3, 25.6]
      east = root.entities.add_group
      east.name = "07_EAST_FACADE"
      west = root.entities.add_group
      west.name = "08_WEST_FACADE"
      end_centers.each_with_index do |cy, i|
        add_window(east.entities, "East Tall Bay #{i + 1}",
                   :x, 60, 1, cy - 1.55, 4.85, 3.10, 6.75, [0.34, 0.68], mats)
        add_window(east.entities, "East Ground Bay #{i + 1}",
                   :x, 60, 1, cy - 0.95, 0.72, 1.90, 2.62, [0.58], mats)
        add_window(west.entities, "West Tall Bay #{i + 1}",
                   :x, 0, -1, cy - 1.55, 4.85, 3.10, 6.75, [0.34, 0.68], mats)
        add_window(west.entities, "West Ground Bay #{i + 1}",
                   :x, 0, -1, cy - 0.95, 0.72, 1.90, 2.62, [0.58], mats)
      end

      entry_glass_e = entry.entities.add_group
      entry_glass_e.name = "Entry east curtain wall"
      add_window(entry_glass_e.entities, "Entry East Curtain",
                 :x, 65.2, 1, 1.0, 0.35, 7.8, 3.55, [0.55], mats)
      add_box(entry_glass_e.entities, "Entry east canopy fin 1", 65.25, 0.85, 3.82, 0.55, 0.12, 0.55, mats[:stone])
      add_box(entry_glass_e.entities, "Entry east canopy fin 2", 65.25, 8.90, 3.82, 0.55, 0.12, 0.55, mats[:stone])

      entry_glass_s = entry.entities.add_group
      entry_glass_s.name = "Entry south curtain wall"
      add_window(entry_glass_s.entities, "Entry South Curtain",
                 :y, 0, -1, 60.35, 0.35, 4.45, 3.55, [0.55], mats)

      annex_windows = annex.entities.add_group
      annex_windows.name = "Annex windows"
      [-9.5, -6.2, -2.9].each_with_index do |cx, i|
        add_window(annex_windows.entities, "Annex South #{i + 1}",
                   :y, 0, -1, cx - 0.85, 0.95, 1.70, 2.25, [0.55], mats)
      end
      [2.4, 6.0, 9.6].each_with_index do |cy, i|
        add_window(annex_windows.entities, "Annex West #{i + 1}",
                   :x, -12, -1, cy - 0.70, 0.95, 1.40, 2.25, [0.55], mats)
      end

      add_box(east.entities, "East sign recess", 59.94, 17.35, 7.45, 0.14, 2.00, 3.25, mats[:canopy])
      add_box(east.entities, "East sign panel", 60.05, 17.55, 7.70, 0.12, 1.60, 2.75, mats[:sign])

      model.options["UnitsOptions"]["LengthUnit"] = 4
      view = model.active_view
      eye = Geom::Point3d.new(86.0 * M, -66.0 * M, 49.0 * M)
      target = Geom::Point3d.new(27.0 * M, 15.0 * M, 6.8 * M)
      view.camera = Sketchup::Camera.new(eye, target, Geom::Vector3d.new(0, 0, 1))
      view.zoom_extents
      view.invalidate

      save_path = "C:/Users/lewis_test/Documents/GitHub/SketchupMCP/SketchUp_Building_Model.skp"
      saved = model.save(save_path)

      model.commit_operation
      {
        success: true,
        saved: saved,
        path: save_path,
        entity_count: model.entities.length,
        groups: model.entities.grep(Sketchup::Group).length,
        bounds_m: {
          min: model.bounds.min.to_a.map { |v| (v / M).round(2) },
          max: model.bounds.max.to_a.map { |v| (v / M).round(2) }
        }
      }
    rescue StandardError => e
      model.abort_operation
      {
        success: false,
        error: e.message,
        backtrace: e.backtrace.first(8)
      }
    end
  end
end

MCPBuildingBuilder.build
