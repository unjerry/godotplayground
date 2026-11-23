# godot47playground

Godot 4.7 first-person bottle sorting prototype.

## Play

Run `gameplay.tscn` with F6, or press F5 (now the project main scene).

- WASD: walk; Space: jump; mouse: look
- E: pick up one loose bottle or a bottle from the targeted shelf slot
- Mouse wheel or keys 1-8: select one of up to 8 carried bottles
- Left click: store the selected bottle in a shelf slot; otherwise throw a RigidBody3D bottle
- Esc: release mouse; left click to recapture; F10: quit

The bottom-left list shows the carried bottles. A green transparent bottle marks
a valid shelf slot; red means the targeted shelf column is full.

Four standalone shelf scenes use `GridMap`; loose bottles use `RigidBody3D`.
Each bottle type is the same MeshLibrary ID in both representations.
Each shelf now has a `ShelfStorage` root script with editable `min_cell`
and `max_cell` Vector3i properties in the Inspector. The bounds include both
endpoints. The initial values match the existing authored bottle coordinates.
To expand or shrink any shelf, select that shelf's root node and edit the
X/Y/Z values. The numbers are local GridMap cell indices, not meter offsets.

Shelf aiming now finds the camera ray's nearest approach to a vertical
bottle-sized axis at EACH permitted GridMap cell. The best on-screen match
wins, across X/Y/Z. Previously, the code chose a Y layer then projected
to its base plane a second time, shifting X/Z toward the far row when the
camera looked down. This second projection is gone. Bottle placement is
still bottom-aligned with `cell_center_y = false`.

Each shelf additionally exports `Aim Radius` (default 0.14m) and
`Aim Height` (default 0.40m). They change only the selection region,
not the stored bottle's position or physical collision. When looking at
shelf furniture but outside any valid slot, LMB will not throw the carried
bottle accidentally.

The highlight is now a flat outline on the selected bottle's base plane.
The highlighted grid cell is the exact cell used by both E and LMB.
Occupied: E picks up that item; empty: LMB stores the carried item. No
automatic search through other rows or Y levels is performed.

`node_3d.tscn` and the existing original shelf scenes remain as editing/test
sandboxes. Models in `assets/` are stored as ZIP files; extract them locally
as in the original project if imported GLB files are missing.

Only the four shelves contain GridMaps. No ground GridMap is used. Loose
bottles and thrown bottles are always RigidBody3D instances. Hidden duplicate
shelves were removed from the showcase to avoid invisible collision blockers.
