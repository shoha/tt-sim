extends Node3D

@export var move_speed: float = 10.0
@export var zoom_speed: float = 20.0
@export var min_zoom: float = 2.0
@export var max_zoom: float = 20.0

@onready var cameraholder_node: Node3D = $WorldEnvironment/CameraHolder
@onready var camera_node: Camera3D = $WorldEnvironment/CameraHolder/Camera3D
@onready var pixelate_node: ColorRect = $WorldEnvironment/PixelateCanvas/Pixelate
