extends Node

## Utility functions for Node tree manipulation.
## Provides helpers for ownership, hierarchy traversal, and node operations.


## Set all children of a node to be owned by that node.
## Useful for programmatically built scene trees that need to be saved.
## @param p_owner: The node that should own all its descendants
func set_own_children(p_owner: Node) -> void:
	for child in p_owner.get_children():
		_set_owner_recursive(p_owner, child)


## Recursively set the owner of a node and all its descendants.
## @param p_owner: The node to set as owner
## @param p_node: The node (and its descendants) to set ownership on
func _set_owner_recursive(p_owner: Node, p_node: Node) -> void:
	p_node.owner = p_owner
	for child in p_node.get_children():
		_set_owner_recursive(p_owner, child)


## Find the first ancestor of a node that matches a type.
## @param node: The starting node
## @param type: The type to search for (use script classes)
## @return: The first matching ancestor, or null if not found
func find_ancestor_of_type(node: Node, type: Variant) -> Node:
	var current = node.get_parent()
	while current:
		if is_instance_of(current, type):
			return current
		current = current.get_parent()
	return null


## Find a child node by type (non-recursive).
## @param parent: The parent node to search in
## @param type: The type to search for
## @return: The first matching child, or null if not found
func find_child_of_type(parent: Node, type: Variant) -> Node:
	for child in parent.get_children():
		if is_instance_of(child, type):
			return child
	return null


## Find all children of a specific type (recursive).
## @param parent: The parent node to search in
## @param type: The type to search for
## @return: Array of all matching descendants
func find_children_of_type(parent: Node, type: Variant) -> Array[Node]:
	var result: Array[Node] = []
	_find_children_of_type_recursive(parent, type, result)
	return result


func _find_children_of_type_recursive(node: Node, type: Variant, result: Array[Node]) -> void:
	for child in node.get_children():
		if is_instance_of(child, type):
			result.append(child)
		_find_children_of_type_recursive(child, type, result)
