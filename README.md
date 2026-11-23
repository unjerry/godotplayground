# godot47playground

Godot 4.7 first-person bottle sorting prototype.

## Play

Run `gameplay.tscn` with F6, or press F5 (now the project main scene).

- WASD: walk; Space: jump; mouse: look
- E: pick up one loose bottle or a bottle from the targeted shelf slot
- Mouse wheel or keys 1-8: select one of up to 8 carried bottles
- Left click: store the selected bottle in a shelf slot or drop it onto the floor
- Esc: release mouse; left click to recapture; F10: quit

The bottom-left list shows the carried bottles. A green transparent bottle marks
a valid drop/store position; red means the targeted shelf column is full.

Four standalone shelf scenes use `GridMap`; loose bottles use `RigidBody3D`.
Each bottle type is the same MeshLibrary ID in both representations.
Shelf interaction is currently restricted to the original painted grid area,
captured at startup. It chooses the front available/occupied depth slot.

`node_3d.tscn` and the existing original shelf scenes remain as editing/test
sandboxes. Models in `assets/` are stored as ZIP files; extract them locally
as in the original project if imported GLB files are missing.
