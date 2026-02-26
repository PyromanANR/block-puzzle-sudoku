extends RefCounted
class_name DialogFactory


static func show_message(parent: Node, title: String, message: String) -> AcceptDialog:
	var dialog = AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	parent.add_child(dialog)
	dialog.popup_centered()
	return dialog
