require "json"

module SushelouModel
  DXF_PATH = "C:/Users/lewis_test/Desktop/sushelou1.dxf"
  OUTPUT_PATH = "C:/Users/lewis_test/Documents/GitHub/SketchupMCP/sushelou_Building_Model.skp"
  PREVIEW_PATH = "C:/Users/lewis_test/Documents/GitHub/SketchupMCP/sushelou_Building_Model_preview.png"
  SOUTH_PATH = "C:/Users/lewis_test/Documents/GitHub/SketchupMCP/sushelou_South.png"
  EAST_PATH = "C:/Users/lewis_test/Documents/GitHub/SketchupMCP/sushelou_East.png"
  ROOF_PATH = "C:/Users/lewis_test/Documents/GitHub/SketchupMCP/sushelou_Roof.png"
  SUMMARY_PATH = "C:/Users/lewis_test/Documents/GitHub/SketchupMCP/sushelou_model_summary.json"

  MM_TO_M = 0.001
  M_TO_IN = 39.37007874015748
  ORIGIN_X_MM = 465_000.0
  LEVELS_M = [0.0, 4.2, 7.8, 11.4, 15.0, 18.6, 22.2]
  BANDS = [
    { floor: 1, min_y: 326_000.0, max_y: 396_000.0 },
    { floor: 2, min_y: 256_000.0, max_y: 326_000.0 },
    { floor: 3, min_y: 187_000.0, max_y: 256_000.0 }
  ]
  ROOF_BAND = { min_y: 116_000.0, max_y: 187_000.0 }

  Entity = Struct.new(
    :type, :layer, :text, :x, :y, :x2, :y2, :points, :closed,
    keyword_init: true
  )

  module_function

  def to_inches(meters)
    meters * M_TO_IN
  end

  def point(x, y, z = 0.0)
    Geom::Point3d.new(to_inches(x), to_inches(y), to_inches(z))
  end

  def read_dxf(path)
    raw = File.open(path, "rb") { |file| file.read }
    lines = raw.force_encoding("UTF-8").split(/\r?\n/)
    entities = []
    current = nil
    in_entities = false
    awaiting_section = false

    finish = lambda do
      next unless current
      current.text = current.text.to_s.gsub(/\\P/i, " ").strip
      entities << current if %w[LINE LWPOLYLINE TEXT MTEXT ATTRIB].include?(current.type)
      current = nil
    end

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
        finish.call
        in_entities = false
        next
      end
      next unless in_entities

      if code == "0"
        finish.call
        current = Entity.new(
          type: value,
          layer: "",
          text: "",
          points: [],
          closed: false
        )
        next
      end
      next unless current

      case code
      when "8"
        current.layer = value
      when "1", "3"
        current.text = current.text.to_s + value
      when "10"
        if current.type == "LWPOLYLINE"
          current.points << [value.to_f, nil]
        else
          current.x = value.to_f
        end
      when "20"
        if current.type == "LWPOLYLINE" && !current.points.empty?
          current.points[-1][1] = value.to_f
        else
          current.y = value.to_f
        end
      when "11"
        current.x2 = value.to_f
      when "21"
        current.y2 = value.to_f
      when "70"
        current.closed = (value.to_i & 1) == 1 if current.type == "LWPOLYLINE"
      end
    end

    finish.call
    entities
  end

  def material(model, name, rgb, alpha = 1.0)
    mat = model.materials[name] || model.materials.add(name)
    mat.color = Sketchup::Color.new(*rgb)
    mat.alpha = alpha
    mat
  end

  def add_box(parent, name, x, y, z, width, depth, height, mat, layer = nil)
    return nil if width <= 0.001 || depth <= 0.001 || height <= 0.001

    group = parent.entities.add_group
    group.name = name
    group.layer = layer if layer
    points = [
      point(x, y, z),
      point(x + width, y, z),
      point(x + width, y + depth, z),
      point(x, y + depth, z)
    ]
    face = group.entities.add_face(points)
    return nil unless face

    face.reverse! if face.normal.z < 0
    face.material = mat
    face.back_material = mat
    face.pushpull(to_inches(height))
    group.material = mat
    group
  end

  def add_slab(parent, name, polygon, z, thickness, mat, layer = nil)
    group = parent.entities.add_group
    group.name = name
    group.layer = layer if layer
    face = group.entities.add_face(polygon.map { |x, y| point(x, y, z) })
    return nil unless face

    face.reverse! if face.normal.z < 0
    face.material = mat
    face.back_material = mat
    face.pushpull(to_inches(-thickness))
    group.material = mat
    group
  end

  def add_vertical_panel(parent, name, x1, y1, z1, x2, y2, z2, mat, layer = nil)
    group = parent.entities.add_group
    group.name = name
    group.layer = layer if layer
    face = group.entities.add_face(
      point(x1, y1, z1),
      point(x2, y2, z1),
      point(x2, y2, z2),
      point(x1, y1, z2)
    )
    return nil unless face

    face.material = mat
    face.back_material = mat
    group.material = mat
    group
  end

  def add_cylinder(parent, name, cx, cy, z, radius, height, mat, layer = nil)
    group = parent.entities.add_group
    group.name = name
    group.layer = layer if layer
    center = point(cx, cy, z)
    edges = group.entities.add_circle(center, Geom::Vector3d.new(0, 0, 1), to_inches(radius), 32)
    face = group.entities.add_face(edges)
    return nil unless face

    face.reverse! if face.normal.z < 0
    face.material = mat
    face.back_material = mat
    face.pushpull(to_inches(height))
    group.material = mat
    group
  end

  def cluster(values, tolerance = 1.0)
    result = []
    values.sort.each do |value|
      if result.empty? || (value - result[-1][-1]).abs > tolerance
        result << [value]
      else
        result[-1] << value
      end
    end
    result.map { |group| group.sum / group.length }
  end

  def in_band?(entity, band)
    return false if entity.y.nil?
    entity.y >= band[:min_y] && entity.y < band[:max_y]
  end

  def normalize_plan(entities, band)
    selected = entities.select { |entity| in_band?(entity, band) }
    lines = selected.select { |entity| entity.type == "LINE" && entity.x2 && entity.y2 }
    wall_lines = lines.select { |line| ["C-墙体", "C-墙柱"].include?(line.layer) }
    raise "No wall lines in plan band #{band.inspect}" if wall_lines.empty?

    xs = wall_lines.flat_map { |line| [line.x, line.x2] }
    ys = wall_lines.flat_map { |line| [line.y, line.y2] }
    min_x = xs.min
    max_x = xs.max
    min_y = ys.min
    max_y = ys.max

    grid_lines = lines.select { |line| line.layer == "C-轴网" }
    horizontal = grid_lines.select do |line|
      (line.y - line.y2).abs < 1.0 && (line.x2 - line.x).abs > 30_000.0
    end
    vertical = grid_lines.select do |line|
      (line.x - line.x2).abs < 1.0 && (line.y2 - line.y).abs > 15_000.0
    end
    grid_ys = cluster(horizontal.map(&:y)).select { |value| value >= min_y - 1.0 && value <= max_y + 1.0 }
    grid_xs = cluster(vertical.map(&:x)).select { |value| value >= min_x - 3_000.0 && value <= max_x + 3_000.0 }
    base_y = grid_ys.empty? ? min_y : grid_ys.min

    {
      min_x: (min_x - ORIGIN_X_MM) * MM_TO_M,
      max_x: (max_x - ORIGIN_X_MM) * MM_TO_M,
      min_y: (min_y - base_y) * MM_TO_M,
      max_y: (max_y - base_y) * MM_TO_M,
      grid_xs: grid_xs.map { |value| (value - ORIGIN_X_MM) * MM_TO_M },
      grid_ys: grid_ys.map { |value| (value - base_y) * MM_TO_M },
      base_y_mm: base_y,
      wall_lines: wall_lines,
      core_lines: wall_lines.select { |line| line.layer == "C-墙体" },
      texts: selected.select { |entity| %w[TEXT MTEXT ATTRIB].include?(entity.type) }
    }
  end

  def add_shell(parent, plan, z, height, mats, layer)
    thickness = 0.24
    x1 = plan[:min_x]
    x2 = plan[:max_x]
    y1 = plan[:min_y]
    y2 = plan[:max_y]

    add_box(parent, "South wall", x1, y1, z, x2 - x1, thickness, height, mats[:brick], layer)
    add_box(parent, "North wall", x1, y2 - thickness, z, x2 - x1, thickness, height, mats[:brick], layer)
    add_box(parent, "West wall", x1, y1 + thickness, z, thickness, y2 - y1 - 2 * thickness, height, mats[:brick], layer)
    add_box(parent, "East wall", x2 - thickness, y1 + thickness, z, thickness, y2 - y1 - 2 * thickness, height, mats[:brick], layer)
    add_box(parent, "Floor band", x1 - 0.06, y1 - 0.06, z + height - 0.14,
            x2 - x1 + 0.12, y2 - y1 + 0.12, 0.14, mats[:stone], layer)
  end

  def add_columns(parent, plan, z, height, mats, layer)
    return 0 if plan[:grid_xs].empty? || plan[:grid_ys].empty?

    count = 0
    plan[:grid_xs].each do |cx|
      next if cx < plan[:min_x] - 0.15 || cx > plan[:max_x] + 0.15
      plan[:grid_ys].each do |cy|
        next if cy < plan[:min_y] - 0.15 || cy > plan[:max_y] + 0.15
        width = 0.58
        depth = 0.72
        add_box(
          parent,
          "Column #{count + 1}",
          cx - width / 2.0,
          cy - depth / 2.0,
          z,
          width,
          depth,
          height,
          mats[:concrete],
          layer
        )
        count += 1
      end
    end
    count
  end

  def add_wall_line(parent, line, plan, z, height, mats, layer, index)
    x1 = (line.x - ORIGIN_X_MM) * MM_TO_M
    y1 = (line.y - plan[:base_y_mm]) * MM_TO_M
    x2 = (line.x2 - ORIGIN_X_MM) * MM_TO_M
    y2 = (line.y2 - plan[:base_y_mm]) * MM_TO_M
    dx = x2 - x1
    dy = y2 - y1
    length = Math.sqrt(dx * dx + dy * dy)
    return false if length < 1.20 || length > 8.0

    near_edge =
      [y1, y2].all? { |value| (value - plan[:min_y]).abs < 0.35 || (value - plan[:max_y]).abs < 0.35 } ||
      [x1, x2].all? { |value| (value - plan[:min_x]).abs < 0.35 || (value - plan[:max_x]).abs < 0.35 }
    return false if near_edge

    thickness = 0.18
    nx = -dy / length * thickness / 2.0
    ny = dx / length * thickness / 2.0
    points = [
      point(x1 + nx, y1 + ny, z),
      point(x2 + nx, y2 + ny, z),
      point(x2 - nx, y2 - ny, z),
      point(x1 - nx, y1 - ny, z)
    ]
    group = parent.entities.add_group
    group.name = "Core wall #{index + 1}"
    group.layer = layer if layer
    face = group.entities.add_face(points)
    return false unless face
    face.reverse! if face.normal.z < 0
    face.material = mats[:brick]
    face.back_material = mats[:brick]
    face.pushpull(to_inches(height))
    group.material = mats[:brick]
    true
  end

  def window_dimensions(label)
    match = label.match(/\A([A-Z]{2,4})(\d{2})(\d{2})/)
    return nil unless match
    {
      prefix: match[1],
      width: match[2].to_i / 10.0,
      height: match[3].to_i / 10.0
    }
  end

  def nearest_side(x, y, plan)
    distances = {
      south: (y - plan[:min_y]).abs,
      north: (y - plan[:max_y]).abs,
      west: (x - plan[:min_x]).abs,
      east: (x - plan[:max_x]).abs
    }
    distances.min_by { |_side, distance| distance }[0]
  end

  def add_frame_box(parent, name, x, y, z, width, depth, height, mat, layer)
    add_box(parent, name, x, y, z, width, depth, height, mat, layer)
  end

  def add_opening(parent, label, plan, z, floor_height, mats, layer, index)
    dims = window_dimensions(label.text)
    return false unless dims

    x = (label.x - ORIGIN_X_MM) * MM_TO_M
    y = (label.y - plan[:base_y_mm]) * MM_TO_M
    return false if x < plan[:min_x] - 2.0 || x > plan[:max_x] + 2.0
    return false if y < plan[:min_y] - 2.0 || y > plan[:max_y] + 2.0

    side = nearest_side(x, y, plan)
    width = [dims[:width], 0.5].max
    height = [dims[:height], 1.2].min
    height = [height, floor_height - 0.45].min
    door = %w[LPM GFM WTM LMC].include?(dims[:prefix])
    sill = door ? 0.02 : 0.88
    z1 = z + sill
    z2 = [z1 + height, z + floor_height - 0.25].min
    return false if z2 - z1 < 0.8

    frame = mats[:frame]
    glass = door ? mats[:wood] : mats[:glass]
    rail = 0.055

    case side
    when :south, :north
      x1 = x - width / 2.0
      x2 = x + width / 2.0
      facade_y = side == :south ? plan[:min_y] - 0.035 : plan[:max_y] + 0.035
      add_vertical_panel(parent, "Opening glass #{index + 1}", x1 + rail, facade_y - 0.012,
                         z1 + rail, x2 - rail, facade_y - 0.012, z2 - rail, glass, layer)
      add_frame_box(parent, "Window left jamb #{index + 1}", x1, facade_y - 0.045, z1,
                    rail, 0.09, z2 - z1, frame, layer)
      add_frame_box(parent, "Window right jamb #{index + 1}", x2 - rail, facade_y - 0.045, z1,
                    rail, 0.09, z2 - z1, frame, layer)
      add_frame_box(parent, "Window sill #{index + 1}", x1, facade_y - 0.045, z1,
                    width, 0.09, rail, frame, layer)
      add_frame_box(parent, "Window head #{index + 1}", x1, facade_y - 0.045, z2 - rail,
                    width, 0.09, rail, frame, layer)
      if width > 1.25
        add_frame_box(parent, "Window mullion #{index + 1}", x - rail / 2.0, facade_y - 0.04, z1,
                      rail, 0.08, z2 - z1, frame, layer)
      end
    when :west, :east
      y1 = y - width / 2.0
      y2 = y + width / 2.0
      facade_x = side == :west ? plan[:min_x] - 0.035 : plan[:max_x] + 0.035
      add_vertical_panel(parent, "Opening glass #{index + 1}", facade_x - 0.012, y1 + rail,
                         z1 + rail, facade_x - 0.012, y2 - rail, z2 - rail, glass, layer)
      add_frame_box(parent, "Window left jamb #{index + 1}", facade_x - 0.045, y1, z1,
                    0.09, rail, z2 - z1, frame, layer)
      add_frame_box(parent, "Window right jamb #{index + 1}", facade_x - 0.045, y2 - rail, z1,
                    0.09, rail, z2 - z1, frame, layer)
      add_frame_box(parent, "Window sill #{index + 1}", facade_x - 0.045, y1, z1,
                    0.09, width, rail, frame, layer)
      add_frame_box(parent, "Window head #{index + 1}", facade_x - 0.045, y1, z2 - rail,
                    0.09, width, rail, frame, layer)
      if width > 1.25
        add_frame_box(parent, "Window mullion #{index + 1}", facade_x - 0.04, y - rail / 2.0, z1,
                      0.08, rail, z2 - z1, frame, layer)
      end
    end
    true
  end

  def add_openings(parent, plan, z, height, mats, layer)
    labels = plan[:texts].select { |text| text.layer == "J-门窗编号" && window_dimensions(text.text) }
    seen = {}
    count = 0
    labels.sort_by { |label| [label.y, label.x] }.each do |label|
      dims = window_dimensions(label.text)
      key = [label.text, (label.x / 150.0).round, (label.y / 150.0).round]
      next if seen[key]
      seen[key] = true
      count += 1 if add_opening(parent, label, plan, z, height, mats, layer, count)
    end
    count
  end

  def build_floor(root, model, mats, plan, index, z, next_z)
    floor = index + 1
    layer_name = format("%02d_Level_%d", floor, floor)
    layer = model.layers[layer_name] || model.layers.add(layer_name)
    group = root.entities.add_group
    group.name = "Level #{floor}"
    group.layer = layer

    height = next_z - z
    polygon = [
      [plan[:min_x], plan[:min_y]],
      [plan[:max_x], plan[:min_y]],
      [plan[:max_x], plan[:max_y]],
      [plan[:min_x], plan[:max_y]]
    ]
    add_slab(group, "Level #{floor} slab", polygon, z, 0.18, mats[:slab], layer)
    add_shell(group, plan, z + 0.02, height - 0.02, mats, layer)
    columns = add_columns(group, plan, z + 0.02, height - 0.02, mats, layer)
    core_walls = 0
    plan[:core_lines].each_with_index do |line, line_index|
      core_walls += 1 if add_wall_line(group, line, plan, z + 0.02, height - 0.04, mats, layer, line_index)
    end
    openings = add_openings(group, plan, z + 0.02, height - 0.04, mats, layer)

    {
      floor: floor,
      layer: layer_name,
      elevation_m: z,
      height_m: height,
      x_m: [plan[:min_x], plan[:max_x]],
      y_m: [plan[:min_y], plan[:max_y]],
      columns: columns,
      core_wall_strips: core_walls,
      openings: openings
    }
  end

  def roof_polyline(entities)
    candidates = entities.select do |entity|
      entity.type == "LWPOLYLINE" &&
        entity.layer == "C-屋面线" &&
        entity.points.length >= 4 &&
        entity.points.all? { |_x, y| y && y >= ROOF_BAND[:min_y] && y < ROOF_BAND[:max_y] }
    end
    raise "No roof polyline found" if candidates.empty?

    candidates.max_by do |entity|
      xs = entity.points.map(&:first)
      ys = entity.points.map(&:last)
      (xs.max - xs.min) * (ys.max - ys.min)
    end
  end

  def roof_grid_base(entities)
    lines = entities.select do |entity|
      entity.type == "LINE" &&
        entity.layer == "C-轴网" &&
        entity.y &&
        entity.y >= ROOF_BAND[:min_y] &&
        entity.y < ROOF_BAND[:max_y] &&
        (entity.y - entity.y2).abs < 1.0 &&
        (entity.x2 - entity.x).abs > 30_000.0
    end
    values = cluster(lines.map(&:y))
    values.empty? ? 142_058.539 : values.min
  end

  def add_edge_wall(parent, name, p1, p2, z, height, thickness, mat, layer)
    x1, y1 = p1
    x2, y2 = p2
    dx = x2 - x1
    dy = y2 - y1
    length = Math.sqrt(dx * dx + dy * dy)
    return if length < 0.1
    nx = -dy / length * thickness / 2.0
    ny = dx / length * thickness / 2.0
    group = parent.entities.add_group
    group.name = name
    group.layer = layer
    face = group.entities.add_face(
      point(x1 + nx, y1 + ny, z),
      point(x2 + nx, y2 + ny, z),
      point(x2 - nx, y2 - ny, z),
      point(x1 - nx, y1 - ny, z)
    )
    return unless face
    face.reverse! if face.normal.z < 0
    face.material = mat
    face.back_material = mat
    face.pushpull(to_inches(height))
    group.material = mat
  end

  def build_roof(root, model, mats, entities)
    roof_layer = model.layers["07_Roof"] || model.layers.add("07_Roof")
    group = root.entities.add_group
    group.name = "Roof"
    group.layer = roof_layer
    base_y = roof_grid_base(entities)
    polyline = roof_polyline(entities)
    polygon = polyline.points.map do |x, y|
      [(x - ORIGIN_X_MM) * MM_TO_M, (y - base_y) * MM_TO_M]
    end
    z = LEVELS_M[-1]
    add_slab(group, "Roof slab", polygon, z, 0.25, mats[:roof], roof_layer)

    polygon.each_with_index do |p1, index|
      p2 = polygon[(index + 1) % polygon.length]
      add_edge_wall(group, "Roof parapet #{index + 1}", p1, p2, z, 0.92, 0.20, mats[:stone], roof_layer)
    end

    xs = polygon.map(&:first)
    ys = polygon.map(&:last)
    xmin = xs.min
    xmax = xs.max
    ymin = ys.min
    ymax = ys.max

    add_box(group, "Accessible roof terrace", xmax - 23.5, ymin + 1.0, z + 0.02,
            21.5, [ymax - ymin - 2.0, 8.2].min, 0.06, mats[:terrace], roof_layer)
    add_box(group, "Unused roof finish", xmin + 1.0, ymin + 1.0, z + 0.02,
            21.0, [ymax - ymin - 2.0, 7.6].min, 0.06, mats[:roof_green], roof_layer)

    add_box(group, "Left roof stair house", 3.0, 9.6, z, 3.6, 5.2, 2.35, mats[:brick], roof_layer)
    add_box(group, "Left roof stair cap", 2.82, 9.42, z + 2.35, 3.96, 5.56, 0.16, mats[:roof], roof_layer)
    add_box(group, "Right roof stair house", xmax - 6.7, 8.7, z, 3.2, 5.8, 2.35, mats[:brick], roof_layer)
    add_box(group, "Right roof stair cap", xmax - 6.9, 8.5, z + 2.35, 3.6, 6.2, 0.16, mats[:roof], roof_layer)
    add_box(group, "Life-water tank room", 5.2, 10.0, z, 7.0, 5.1, 2.15, mats[:brick], roof_layer)
    add_box(group, "Life-water tank room cap", 5.0, 9.8, z + 2.15, 7.4, 5.5, 0.16, mats[:roof], roof_layer)
    add_box(group, "Fire-water tank room", 19.3, 10.1, z, 8.0, 5.0, 2.15, mats[:brick], roof_layer)
    add_box(group, "Fire-water tank room cap", 19.1, 9.9, z + 2.15, 8.4, 5.4, 0.16, mats[:roof], roof_layer)

    add_cylinder(group, "Life-water tank", 8.7, 12.4, z + 0.02, 2.35, 2.0, mats[:metal], roof_layer)
    add_cylinder(group, "Fire-water tank", 23.3, 12.6, z + 0.02, 3.2, 2.0, mats[:metal], roof_layer)

    {
      elevation_m: z,
      polygon_points: polygon.length,
      x_m: [xmin, xmax],
      y_m: [ymin, ymax],
      note: "Roof boundary read from C-屋面线; modeled as flat roof with the drawing outline."
    }
  end

  def add_site(root, model, mats, plans)
    layer = model.layers["00_Site"] || model.layers.add("00_Site")
    group = root.entities.add_group
    group.name = "Site"
    group.layer = layer
    add_box(group, "Site ground", -11.0, -12.0, -0.35, 78.0, 43.0, 0.35, mats[:grass], layer)
    add_box(group, "South walkway", -3.0, -5.8, -0.03, 64.0, 4.2, 0.08, mats[:paving], layer)
    add_box(group, "Entrance plinth", -1.8, -2.0, 0.0, 7.8, 2.6, 0.18, mats[:stone], layer)
    add_box(group, "Entrance canopy", -2.4, -2.0, 3.25, 6.8, 2.6, 0.22, mats[:roof], layer)
    add_cylinder(group, "Entrance column west", -0.8, -0.6, 0.0, 0.18, 3.25, mats[:metal], layer)
    add_cylinder(group, "Entrance column east", 4.2, -0.6, 0.0, 0.18, 3.25, mats[:metal], layer)
    group
  end

  def remove_old_model(model)
    model.close_active while model.active_entities != model.entities
    model.entities.grep(Sketchup::Group).select { |group| group.name == "SUSHELOU_MODEL" }.each(&:erase!)
    model.materials.to_a.select { |mat| mat.name.start_with?("SUSHELOU ") }.each do |mat|
      model.materials.remove(mat) if mat.valid?
    end
  end

  def camera(view, eye, target, up = Geom::Vector3d.new(0, 0, 1), perspective = true)
    view.camera = Sketchup::Camera.new(eye, target, up, perspective)
    view.invalidate
  end

  def create_scenes(model, plans)
    view = model.active_view
    model.pages.to_a.each { |page| model.pages.erase(page) }
    width = plans.values.map { |plan| plan[:max_x] }.max
    depth = plans.values.map { |plan| plan[:max_y] }.max - plans.values.map { |plan| plan[:min_y] }.min
    center = Geom::Point3d.new(to_inches(width * 0.5), to_inches(depth * 0.45), to_inches(10.8))

    camera(
      view,
      Geom::Point3d.new(to_inches(83), to_inches(-48), to_inches(36)),
      center,
      Geom::Vector3d.new(0, 0, 1),
      true
    )
    model.pages.add("01_Overview")

    camera(
      view,
      Geom::Point3d.new(to_inches(width * 0.5), to_inches(-72), to_inches(12.0)),
      Geom::Point3d.new(to_inches(width * 0.5), to_inches(depth * 0.45), to_inches(11.8)),
      Geom::Vector3d.new(0, 0, 1),
      false
    )
    model.pages.add("02_South_Elevation")

    camera(
      view,
      Geom::Point3d.new(to_inches(width + 62), to_inches(depth * 0.45), to_inches(12.0)),
      Geom::Point3d.new(to_inches(width * 0.45), to_inches(depth * 0.45), to_inches(11.8)),
      Geom::Vector3d.new(0, 0, 1),
      false
    )
    model.pages.add("03_East_Elevation")

    model.shadow_info["DisplayShadows"] = false
    camera(
      view,
      Geom::Point3d.new(to_inches(width * 0.5), to_inches(depth * 0.45), to_inches(72)),
      Geom::Point3d.new(to_inches(width * 0.5), to_inches(depth * 0.45), to_inches(22.2)),
      Geom::Vector3d.new(0, 1, 0),
      false
    )
    model.pages.add("04_Roof_Plan")
    model.shadow_info["DisplayShadows"] = true

    model.pages.selected_page = model.pages["01_Overview"]
    camera(
      view,
      Geom::Point3d.new(to_inches(83), to_inches(-48), to_inches(36)),
      center,
      Geom::Vector3d.new(0, 0, 1),
      true
    )
  end

  def write_image(view, path, width, height)
    view.write_image(path, width, height, true)
    true
  rescue StandardError => error
    error.message
  end

  def build
    model = Sketchup.active_model
    entities = read_dxf(DXF_PATH)
    plan1 = normalize_plan(entities, BANDS[0])
    plan2 = normalize_plan(entities, BANDS[1])
    plan3 = normalize_plan(entities, BANDS[2])
    plans_by_floor = { 1 => plan1, 2 => plan2, 3 => plan3 }

    model.start_operation("Create sushelou dormitory from seven floor plans", true)
    begin
      remove_old_model(model)

      mats = {
        brick: material(model, "SUSHELOU Brick", [125, 67, 52]),
        stone: material(model, "SUSHELOU Stone", [218, 215, 203]),
        slab: material(model, "SUSHELOU Slab", [211, 211, 204]),
        concrete: material(model, "SUSHELOU Concrete", [166, 169, 164]),
        glass: material(model, "SUSHELOU Glass", [57, 103, 116], 0.72),
        frame: material(model, "SUSHELOU Window Frame", [42, 49, 49]),
        roof: material(model, "SUSHELOU Roof", [67, 72, 70]),
        terrace: material(model, "SUSHELOU Roof Terrace", [183, 174, 151]),
        roof_green: material(model, "SUSHELOU Roof Planted", [91, 111, 91]),
        metal: material(model, "SUSHELOU Brushed Metal", [176, 181, 179]),
        wood: material(model, "SUSHELOU Door", [108, 72, 48]),
        grass: material(model, "SUSHELOU Site Grass", [104, 125, 99]),
        paving: material(model, "SUSHELOU Site Paving", [166, 164, 153])
      }

      root = model.entities.add_group
      root.name = "SUSHELOU_MODEL"
      add_site(root, model, mats, plans_by_floor)

      summaries = []
      (0...6).each do |index|
        floor = index + 1
        plan = if floor == 1
                 plan1
               elsif floor == 2
                 plan2
               else
                 plan3
               end
        summaries << build_floor(root, model, mats, plan, index, LEVELS_M[index], LEVELS_M[index + 1])
      end
      roof_summary = build_roof(root, model, mats, entities)

      model.options["UnitsOptions"]["LengthUnit"] = 4
      model.options["UnitsOptions"]["LengthFormat"] = 0
      model.shadow_info["DisplayShadows"] = true
      create_scenes(model, plans_by_floor)
      model.active_view.zoom_extents
      model.save(OUTPUT_PATH)

      view = model.active_view
      camera(
        view,
        Geom::Point3d.new(to_inches(83), to_inches(-48), to_inches(36)),
        Geom::Point3d.new(to_inches(27), to_inches(7.5), to_inches(10.8)),
        Geom::Vector3d.new(0, 0, 1),
        true
      )
      model.active_view.zoom_extents
      preview = write_image(view, PREVIEW_PATH, 1800, 1100)

      camera(
        view,
        Geom::Point3d.new(to_inches(27), to_inches(-72), to_inches(12)),
        Geom::Point3d.new(to_inches(27), to_inches(7.5), to_inches(11.8)),
        Geom::Vector3d.new(0, 0, 1),
        false
      )
      model.active_view.zoom_extents
      south = write_image(view, SOUTH_PATH, 1800, 1000)

      camera(
        view,
        Geom::Point3d.new(to_inches(115), to_inches(7.5), to_inches(12)),
        Geom::Point3d.new(to_inches(27), to_inches(7.5), to_inches(11.8)),
        Geom::Vector3d.new(0, 0, 1),
        false
      )
      model.active_view.zoom_extents
      east = write_image(view, EAST_PATH, 1300, 1000)

      model.shadow_info["DisplayShadows"] = false
      camera(
        view,
        Geom::Point3d.new(to_inches(27), to_inches(7.5), to_inches(72)),
        Geom::Point3d.new(to_inches(27), to_inches(7.5), to_inches(22.2)),
        Geom::Vector3d.new(0, 1, 0),
        false
      )
      model.active_view.zoom_extents
      roof = write_image(view, ROOF_PATH, 1800, 1000)
      model.shadow_info["DisplayShadows"] = true

      model.pages.selected_page = model.pages["01_Overview"]
      model.save(OUTPUT_PATH)
      summary = {
        success: true,
        saved: OUTPUT_PATH,
        source: DXF_PATH,
        previews: {
          overview: preview,
          south: south,
          east: east,
          roof: roof
        },
        floor_levels_m: LEVELS_M,
        floors: summaries,
        roof: roof_summary,
        bounds_m: {
          min: model.bounds.min.to_a.map { |value| (value / M_TO_IN).round(3) },
          max: model.bounds.max.to_a.map { |value| (value / M_TO_IN).round(3) }
        },
        scenes: model.pages.map(&:name)
      }
      File.write(SUMMARY_PATH, JSON.pretty_generate(summary))
      model.commit_operation
      JSON.generate(summary)
    rescue StandardError => error
      model.abort_operation
      JSON.generate(
        success: false,
        error: error.message,
        class: error.class.name,
        backtrace: error.backtrace.first(16)
      )
    end
  end
end

SushelouModel.build
