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

The camera ray is tested against each permitted 3D slot volume. The nearest
intersected slot is highlighted and is the exact slot used by E and LMB:
E only picks up a bottle in that occupied cell; LMB only stores in that empty
cell. It no longer jumps to another level or automatically selects a rear row.
A 3D wireframe around the target cell shows which volume is selected.

`node_3d.tscn` and the existing original shelf scenes remain as editing/test
sandboxes. Models in `assets/` are stored as ZIP files; extract them locally
as in the original project if imported GLB files are missing.

Only the four shelves contain GridMaps. No ground GridMap is used. Loose
bottles and thrown bottles are always RigidBody3D instances. Hidden duplicate
shelves were removed from the showcase to avoid invisible collision blockers.
