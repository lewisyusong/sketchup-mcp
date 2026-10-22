module ShiSUModelBuilder
  M = 39.37007874015748
  MM_TO_M = 0.001
  PLANE_OFFSET = 0.025

  DXF_PATH = "C:/Users/lewis_test/Documents/BaiduSyncdisk/临汾三中/shiSU.dxf"
  OUTPUT_PATH = "C:/Users/lewis_test/Documents/GitHub/SketchupMCP/shiSU_Building_Model.skp"
  PREVIEW_PATH = "C:/Users/lewis_test/Documents/GitHub/SketchupMCP/shiSU_Building_Model_preview.png"

  BASE_Y_MM = 56_756.0058486593
  WIDTH_M = 34.900
  DEPTH_M = 54.76607
  MAIN_HEIGHT_M = 15.300
  TOTAL_HEIGHT_M = 18.300

  VIEWS = [
    { name: "South", min_x: -140_963.088758302, max_x: -106_063.088758302 },
    { name: "West",  min_x: -86_077.118758302,  max_x: -31_311.048758302 },
    { name: "North", min_x: -11_665.088758302,  max_x: 23_234.911241698 },
    { name: "East",  min_x: 44_262.882882392,   max_x: 99_028.952882392 }
  ]

  Segment = Struct.new(:x1, :y1, :x2, :y2)

  module_function

  def inches(meters)
    meters * M
  end

  def read_dxf_lines(path)
    lines = File.read(path, mode: "r:BOM|UTF-8").split(/\r?\n/)
    segments = []
    in_entities = false
    awaiting_section = false
    current = nil

    (0...(lines.length - 1)).step(2) do |index|
      code = lines[index].strip
      value = lines[index + 1].strip

      if code == "0" && value == "SECTION"
        awaiting_section = true
        next
      end
      if awaiting_section && code == "2"
        in_entities = value == "ENTITIES"
        awaiting_section = false
        next
      end
      if code == "0" && value == "ENDSEC"
        in_entities = false
        next
      end
      next unless in_entities

      if code == "0"
        if current && current[:type] == "LINE"
          segments << Segment.new(
            current[:x1].to_f,
            current[:y1].to_f,
            current[:x2].to_f,
            current[:y2].to_f
          )
        end
        current = { type: value }
        next
      end

      next unless current
      case code
      when "10" then current[:x1] = value
      when "20" then current[:y1] = value
      when "11" then current[:x2] = value
      when "21" then current[:y2] = value
      end
    end

    if current && current[:type] == "LINE"
      segments << Segment.new(
        current[:x1].to_f,
        current[:y1].to_f,
        current[:x2].to_f,
        current[:y2].to_f
      )
    end

    segments
  end

  def material(model, name, rgb, alpha = 1.0)
    mat = model.materials.add(name)
    mat.color = Sketchup::Color.new(*rgb)
    mat.alpha = alpha
    mat
  end

  def add_box(parent, name, x, y, z, width, depth, height, material)
    return nil if width.abs < 0.001 || depth.abs < 0.001 || height.abs < 0.001

    group = parent.add_group
    group.name = name
    points = [
      Geom::Point3d.new(inches(x), inches(y), inches(z)),
      Geom::Point3d.new(inches(x + width), inches(y), inches(z)),
      Geom::Point3d.new(inches(x + width), inches(y + depth), inches(z)),
      Geom::Point3d.new(inches(x), inches(y + depth), inches(z))
    ]
    face = group.entities.add_face(points)
    face.reverse! if face.normal.z < 0
    face.pushpull(inches(height))
    group.material = material
    group
  end

  def plane_point(view_name, u_m, z_m)
    x = nil
    y = nil

    case view_name
    when "South"
      x = u_m
      y = -PLANE_OFFSET
    when "West"
      x = -PLANE_OFFSET
      y = DEPTH_M - u_m
    when "North"
      x = WIDTH_M - u_m
      y = DEPTH_M + PLANE_OFFSET
    when "East"
      x = WIDTH_M + PLANE_OFFSET
      y = u_m
    end

    Geom::Point3d.new(inches(x), inches(y), inches(z_m))
  end

  def build_facade(parent, view, raw_segments, brick, stone, glass, frame)
    min_x = view[:min_x]
    max_x = view[:max_x]
    span_mm = max_x - min_x
    group = parent.entities.add_group
    group.name = "#{view[:name]} facade"

    seen = {}
    created = 0
    raw_segments.each do |segment|
      next if [segment.x1, segment.x2].max < min_x || [segment.x1, segment.x2].min > max_x

      u1 = (segment.x1 - min_x) / 1000.0
      u2 = (segment.x2 - min_x) / 1000.0
      z1 = (segment.y1 - BASE_Y_MM) / 1000.0
      z2 = (segment.y2 - BASE_Y_MM) / 1000.0
      key_a = [u1.round(5), z1.round(5)]
      key_b = [u2.round(5), z2.round(5)]
      key = (key_a <=> key_b) <= 0 ? [key_a, key_b] : [key_b, key_a]
      next if seen[key]

      seen[key] = true
      p1 = plane_point(view[:name], u1, z1)
      p2 = plane_point(view[:name], u2, z2)
      next if p1.distance(p2) < 0.001

      edge = group.entities.add_line(p1, p2)
      created += 1 if edge && edge.valid?
    end

    group.entities.grep(Sketchup::Edge).each(&:find_faces)

    glass_faces = 0
    stone_faces = 0
    group.entities.grep(Sketchup::Face).each do |face|
      bbox = face.bounds
      area_m2 = face.area / (M * M)
      dimensions = [
        (bbox.max.x - bbox.min.x) / M,
        (bbox.max.y - bbox.min.y) / M,
        (bbox.max.z - bbox.min.z) / M
      ].select { |value| value > 0.01 }.sort
      next if dimensions.length < 2

      shortest = dimensions[0]
      middle = dimensions[1]
      longest = dimensions[-1]
      center_z = (bbox.min.z + bbox.max.z) * 0.5 / M

      face.material = brick
      face.back_material = brick

      if center_z < MAIN_HEIGHT_M - 0.12 &&
         shortest < 0.34 && middle >= 0.75 && longest <= 7.0
        face.material = stone
        face.back_material = stone
        stone_faces += 1
      elsif area_m2 >= 0.12 && area_m2 <= 8.5 &&
         shortest >= 0.34 && middle >= 0.50 && longest <= 4.2 &&
         center_z >= 0.08 && center_z <= MAIN_HEIGHT_M - 0.03
        face.material = glass
        face.back_material = glass
        glass_faces += 1
      end
    end

    group
  end

  def remove_old_model(model)
    model.close_active while model.active_entities != model.entities
    model.entities.grep(Sketchup::Group)
         .select { |group| group.name == "SHISU_MODEL" }
         .each(&:erase!)
    model.materials.to_a
         .select { |mat| mat.name.start_with?("SHISU ") }
         .each { |mat| model.materials.remove(mat) if mat.valid? }
  end

  def set_camera(view, eye, target, up = Geom::Vector3d.new(0, 0, 1), perspective = true)
    view.camera = Sketchup::Camera.new(eye, target, up, perspective)
    view.invalidate
  end

  def create_scenes(model)
    view = model.active_view

    model.pages.to_a.each { |page| model.pages.erase(page) } if model.pages.length > 0

    set_camera(
      view,
      Geom::Point3d.new(inches(WIDTH_M + 31), inches(DEPTH_M + 38), inches(28)),
      Geom::Point3d.new(inches(WIDTH_M * 0.45), inches(DEPTH_M * 0.47), inches(8.5))
    )
    view.zoom_extents
    model.pages.add("01_Perspective")

    [
      ["02_South_Elevation", "South"],
      ["03_West_Elevation", "West"],
      ["04_North_Elevation", "North"],
      ["05_East_Elevation", "East"]
    ].each do |page_name, side|
      case side
      when "South"
        eye = Geom::Point3d.new(inches(WIDTH_M * 0.5), inches(-90), inches(TOTAL_HEIGHT_M * 0.5))
        target = Geom::Point3d.new(inches(WIDTH_M * 0.5), inches(DEPTH_M), inches(TOTAL_HEIGHT_M * 0.5))
      when "West"
        eye = Geom::Point3d.new(inches(-90), inches(DEPTH_M * 0.5), inches(TOTAL_HEIGHT_M * 0.5))
        target = Geom::Point3d.new(inches(WIDTH_M), inches(DEPTH_M * 0.5), inches(TOTAL_HEIGHT_M * 0.5))
      when "North"
        eye = Geom::Point3d.new(inches(WIDTH_M * 0.5), inches(DEPTH_M + 90), inches(TOTAL_HEIGHT_M * 0.5))
        target = Geom::Point3d.new(inches(WIDTH_M * 0.5), inches(0), inches(TOTAL_HEIGHT_M * 0.5))
      when "East"
        eye = Geom::Point3d.new(inches(WIDTH_M + 90), inches(DEPTH_M * 0.5), inches(TOTAL_HEIGHT_M * 0.5))
        target = Geom::Point3d.new(inches(0), inches(DEPTH_M * 0.5), inches(TOTAL_HEIGHT_M * 0.5))
      end
      set_camera(view, eye, target, Geom::Vector3d.new(0, 0, 1), false)
      view.zoom_extents
      model.pages.add(page_name)
    end

    model.pages.selected_page = model.pages["01_Perspective"]
    set_camera(
      view,
      Geom::Point3d.new(inches(WIDTH_M + 31), inches(DEPTH_M + 38), inches(28)),
      Geom::Point3d.new(inches(WIDTH_M * 0.45), inches(DEPTH_M * 0.47), inches(8.5))
    )
    view.zoom_extents
    view.invalidate
  end

  def build
    model = Sketchup.active_model
    raw_segments = read_dxf_lines(DXF_PATH)

    model.start_operation("Create shiSU building from four elevations", true)
    begin
      remove_old_model(model)

      materials = {
        brick: material(model, "SHISU Brick", [126, 66, 50]),
        brick_dark: material(model, "SHISU Brick Base", [91, 48, 39]),
        stone: material(model, "SHISU Stone", [214, 211, 200]),
        roof: material(model, "SHISU Roof", [72, 74, 74]),
        glass: material(model, "SHISU Glass", [75, 101, 112], 0.82),
        frame: material(model, "SHISU Window Frame", [38, 41, 42])
      }

      root = model.entities.add_group
      root.name = "SHISU_MODEL"

      massing = root.entities.add_group
      massing.name = "Massing"
      add_box(massing.entities, "Main volume", 0, 0, 0, WIDTH_M, DEPTH_M, MAIN_HEIGHT_M, materials[:brick])
      add_box(massing.entities, "Base course", -0.18, -0.18, 0, WIDTH_M + 0.36, DEPTH_M + 0.36, 0.52, materials[:brick_dark])
      add_box(massing.entities, "Main cornice", -0.30, -0.30, MAIN_HEIGHT_M - 0.16,
              WIDTH_M + 0.60, DEPTH_M + 0.60, 0.16, materials[:stone])

      crown_depth = 48.10
      crown_y = (DEPTH_M - crown_depth) * 0.5
      add_box(massing.entities, "Rooftop recessed volume", 0, crown_y, MAIN_HEIGHT_M,
              WIDTH_M, crown_depth, TOTAL_HEIGHT_M - MAIN_HEIGHT_M, materials[:brick])
      add_box(massing.entities, "Rooftop cap", -0.42, crown_y - 0.42, TOTAL_HEIGHT_M,
              WIDTH_M + 0.84, crown_depth + 0.84, 0.22, materials[:roof])
      add_box(massing.entities, "Roof parapet cap", -0.22, crown_y - 0.22, TOTAL_HEIGHT_M + 0.22,
              WIDTH_M + 0.44, crown_depth + 0.44, 0.12, materials[:stone])

      face_summary = []
      VIEWS.each do |view|
        facade = build_facade(
          root,
          view,
          raw_segments,
          materials[:brick],
          materials[:stone],
          materials[:glass],
          materials[:frame]
        )
        face_summary << {
          name: view[:name],
          edges: facade.entities.grep(Sketchup::Edge).length,
          faces: facade.entities.grep(Sketchup::Face).length
        }
      end

      ground = root.entities.add_group
      ground.name = "Site base"
      add_box(ground.entities, "Ground plane", -10, -10, -0.45, WIDTH_M + 20, DEPTH_M + 20, 0.45, materials[:stone])

      create_scenes(model)
      model.options["UnitsOptions"]["LengthUnit"] = 4
      model.active_view.invalidate
      saved = model.save(OUTPUT_PATH)

      preview_written = true
      begin
        model.active_view.write_image(PREVIEW_PATH, 1800, 1100, true)
      rescue StandardError => image_error
        preview_written = image_error.message
      end

      model.commit_operation
      {
        success: true,
        saved: saved,
        path: OUTPUT_PATH,
        preview: preview_written,
        raw_lines: raw_segments.length,
        facades: face_summary,
        bounds_m: {
          min: model.bounds.min.to_a.map { |v| (v / M).round(3) },
          max: model.bounds.max.to_a.map { |v| (v / M).round(3) }
        }
      }
    rescue StandardError => e
      model.abort_operation
      {
        success: false,
        error: e.message,
        class: e.class.name,
        backtrace: e.backtrace.first(10)
      }
    end
  end
end

ShiSUModelBuilder.build
