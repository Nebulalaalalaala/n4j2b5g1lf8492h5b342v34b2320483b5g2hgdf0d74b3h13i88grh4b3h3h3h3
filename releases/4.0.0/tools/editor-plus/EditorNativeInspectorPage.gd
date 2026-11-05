extends LevelEditor_InspectorPanel

# Participates in the native inspector's panel switching/render_nodes contract.
# The existing Properties/Position/Rotation panels stay unchanged.
var integration

func render_nodes(_nodes: Array):
	if integration != null:
		integration.refresh()
