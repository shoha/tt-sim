extends Node

func set_own_children(p_owner: Node):
  for child in p_owner.get_children():
    set_owner_recursive(p_owner, child)

func set_owner_recursive(p_owner: Node, p_node: Node):
    # Set the owner of the current node
    p_node.owner = p_owner

    # Recursively call the function for all children
    for child in p_node.get_children():
        set_owner_recursive(p_owner, child)
