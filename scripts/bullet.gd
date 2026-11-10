extends Area2D

@export var speed := 300.0
@export var lifetime := 1.5

var direction := Vector2.RIGHT


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta


func _on_body_entered(_body: Node) -> void:
	queue_free()


func _draw() -> void:
	draw_rect(Rect2(-2, -2, 4, 4), Color("ffe066"))
