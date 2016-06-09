data:extend({
    {
        type = "decorative",
        name = "belt-overflow-indicator",
        flags = {"placeable-neutral", "not-on-map"},
        icon = "__belt-overflow__/graphics/indicator.png",
        collision_mask = { "ghost-layer"},
        subgroup = "grass",
        order = "b[decorative]-b[belt-overflow-indicator]",
        collision_box = {{-0.4, -0.4}, {0.4, 0.4}},
        selection_box = {{-0.5, -0.5}, {0.5, 0.5}},
        selectable_in_game = false,
        render_layer = "wires",
        pictures = {
            {
                filename = "__belt-overflow__/graphics/indicator.png",
                width = 32,
                height = 32
            }
        }
    },

    {
        type = "decorative",
        name = "belt-overflow-indicator-wide",
        flags = {"placeable-neutral", "not-on-map"},
        icon = "__belt-overflow__/graphics/indicator-wide.png",
        collision_mask = { "ghost-layer"},
        subgroup = "grass",
        order = "b[decorative]-b[belt-overflow-indicator-wide]",
        collision_box = {{-0.9, -0.4}, {0.9, 0.4}},
        selection_box = {{-1, -0.5}, {1, 0.5}},
        selectable_in_game = false,
        render_layer = "wires",
        pictures = {
            {
                filename = "__belt-overflow__/graphics/indicator-wide.png",
                width = 64,
                height = 32
            }
        }
    },
-- "Entity direction can not be set on entity type: decorative" :(
    {
        type = "decorative",
        name = "belt-overflow-indicator-tall",
        flags = {"placeable-neutral", "not-on-map"},
        icon = "__belt-overflow__/graphics/indicator-tall.png",
        collision_mask = { "ghost-layer"},
        subgroup = "grass",
        order = "b[decorative]-b[belt-overflow-indicator-tall]",
        collision_box = {{-0.4, -0.9}, {0.4, 0.9}},
        selection_box = {{-0.5, -1}, {0.5, 1}},
        selectable_in_game = false,
        render_layer = "wires",
        pictures = {
            {
                filename = "__belt-overflow__/graphics/indicator-tall.png",
                width = 32,
                height = 64
            }
        }
    },
})