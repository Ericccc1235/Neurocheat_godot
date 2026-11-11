extends Node3D

# ==============================================================================
# NeuroCheat 3D - Godot 4 完整 3D 第一人稱考場與生醫訊號系統
# Group 6: B13502162 黃建澄 | B13901094 王家佑 | B13901135 張嘉宸
# ==============================================================================

const ECGScopeScript = preload("res://scripts/ecg_scope.gd")

enum GameState { TITLE, PLAYING, BUSTED, TIMEOUT_FAIL, VICTORY }
enum BioMode { MANUAL, EXTERNAL }
enum TeacherState { WRITING_BOARD, BUZZER_WARNING, FALSE_ALARM, TURNING_AROUND, PATROLLING, RETURNING }

var game_state: GameState = GameState.TITLE
var bio_mode: BioMode = BioMode.MANUAL

# --- 生理訊號狀態 (EMG / ECG / EEG) ---
var emg_active: bool = false
var emg_level: float = 0.0        # 0.0 (抽屜關閉) ~ 1.0 (伸手拉開抽屜並展開小抄)
var base_bpm: float = 72.0
var ecg_bpm: float = 72.0
var is_deep_breathing: bool = false
var beat_phase: float = 0.0
var eeg_focus: float = 75.0
var eeg_target_focus: float = 75.0

# --- 外部訊號接收 (UDP 127.0.0.1:5005 & JSON) ---
var udp_server: PacketPeerUDP = PacketPeerUDP.new()
var external_source_name: String = "等待外部訊號"
var external_packet_count: int = 0
var last_external_time: float = -100.0

# --- 考題資料庫 (10 題完整生醫與電資考題) ---
var questions: Array[Dictionary] = [
	{
		"prompt": "Q1. 傅立葉轉換 (Fourier Transform) 主要將時域訊號轉換至哪一個領域？",
		"options": ["A. 頻率域 (Frequency)", "B. 空間域 (Spatial)", "C. 複數拉氏域 (s-domain)", "D. 離散小波域 (Wavelet)"],
		"correct": 0,
		"hint": "Q1 答案選 [A] • FT 本質是分解成正弦波頻率分量 (時域 -> 頻域)。",
		"user_ans": -1
	},
	{
		"prompt": "Q2. 根據奈奎斯特抽樣定理 (Nyquist Theorem)，若心電訊號最高頻率為 150 Hz，抽樣頻率至少需大於多少才不會發生混疊 (Aliasing)？",
		"options": ["A. 75 Hz", "B. 150 Hz", "C. 300 Hz", "D. 600 Hz"],
		"correct": 2,
		"hint": "Q2 答案選 [C] • fs >= 2 * f_max = 2 * 150 = 300 Hz。",
		"user_ans": -1
	},
	{
		"prompt": "Q3. 腦電圖 (EEG) 中，受試者清醒放鬆、閉目養神時最顯著的腦波波段是？",
		"options": ["A. Delta 波 (0.5-4 Hz)", "B. Theta 波 (4-8 Hz)", "C. Alpha 波 (8-13 Hz)", "D. Beta 波 (13-30 Hz)"],
		"correct": 2,
		"hint": "Q3 答案選 [C] • 清醒閉眼放鬆為 Alpha 波；高度專注思考為 Beta 波。",
		"user_ans": -1
	},
	{
		"prompt": "Q4. 標準心電圖 (ECG) 波形中，代表「心室去極化 (Ventricular Depolarization)」的是哪一個波群？",
		"options": ["A. P 波", "B. QRS 波群", "C. T 波", "D. U 波"],
		"correct": 1,
		"hint": "Q4 答案選 [B] • P波是心房去極化，QRS波群是心室去極化，T波是心室再極化。",
		"user_ans": -1
	},
	{
		"prompt": "Q5. 量測表面肌電訊號 (sEMG) 時，為了消除台灣市電造成的電源雜訊，應使用幾 Hz 的陷波濾波器 (Notch Filter)？",
		"options": ["A. 50 Hz", "B. 60 Hz", "C. 100 Hz", "D. 120 Hz"],
		"correct": 1,
		"hint": "Q5 答案選 [B] • 台灣市電頻率為 60 Hz，需用 60 Hz Band-stop 濾除。",
		"user_ans": -1
	},
	{
		"prompt": "Q6. 生醫儀表放大器 (Instrumentation Amplifier) 最關鍵的特性為何？",
		"options": ["A. 低輸入阻抗", "B. 高共模拒斥比 (High CMRR)", "C. 高輸出阻抗", "D. 非線性相位失真"],
		"correct": 1,
		"hint": "Q6 答案選 [B] • 生醫訊號微弱且共模雜訊大，必須具備極高 CMRR 與高輸入阻抗。",
		"user_ans": -1
	},
	{
		"prompt": "Q7. 正常成年人在安靜狀態下的竇性心律 (Normal Sinus Rhythm) 範圍約為每分鐘幾次 (BPM)？",
		"options": ["A. 30 - 50 BPM", "B. 60 - 100 BPM", "C. 110 - 150 BPM", "D. 150 - 200 BPM"],
		"correct": 1,
		"hint": "Q7 答案選 [B] • 60~100 BPM 為正常心率，超過 100 BPM 稱為竇性心搏過速。",
		"user_ans": -1
	},
	{
		"prompt": "Q8. 進行 EEG 專注度分析時，通常計算哪兩個頻帶的能量比值來評估受試者專注程度？",
		"options": ["A. Beta / (Alpha + Theta)", "B. Delta / Gamma", "C. Alpha / Beta", "D. Theta / Delta"],
		"correct": 0,
		"hint": "Q8 答案選 [A] • Beta 代表專注活躍，Alpha+Theta 代表放鬆昏沉，比值越高越專注。",
		"user_ans": -1
	},
	{
		"prompt": "Q9. Ag/AgCl (銀/氯化銀) 電極在生醫量測中被廣泛採用，主要是因為它屬於哪種電極？",
		"options": ["A. 完全極化電極", "B. 接近非極化電極 (Non-polarizable)", "C. 電容耦合電極", "D. 光電感測電極"],
		"correct": 1,
		"hint": "Q9 答案選 [B] • Ag/AgCl 半電池電位穩定、移動假影最小，屬非極化電極。",
		"user_ans": -1
	},
	{
		"prompt": "Q10. 在類比轉數位轉換器 (ADC) 中，若使用 12-bit ADC 量測 0 ~ 3.3V 的生醫訊號，其電壓解析度約為多少？",
		"options": ["A. 0.805 mV", "B. 3.22 mV", "C. 12.8 mV", "D. 0.102 mV"],
		"correct": 0,
		"hint": "Q10 答案選 [A] • 3.3V / (2^12) = 3.3 / 4096 ≈ 0.000805V = 0.805 mV。",
		"user_ans": -1
	}
]
var current_q_idx: int = 0
var time_left: float = 120.0

# --- 奶龍監考官 AI 狀態 ---
var teacher_state: TeacherState = TeacherState.WRITING_BOARD
var teacher_timer: float = 5.5
var patrol_progress: float = 0.0   # 0.0 在黑板前 -> 1.0 走到玩家桌前
var buzzer_active: bool = false
var facing_player: bool = false
var suspicion_level: float = 0.0

# --- 3D 節點參照 ---
var camera: Camera3D
var cam_yaw: float = 0.0
var cam_pitch: float = -0.32
var target_yaw: float = 0.0
var target_pitch: float = -0.32

var exam_viewport: SubViewport
var exam_mesh_inst: MeshInstance3D
var exam_q_label: Label
var exam_header_label: Label
var exam_opt_panels: Array[Panel] = []
var exam_opt_labels: Array[Label] = []
var exam_btn_prev: Panel
var exam_btn_next: Panel
var exam_btn_submit: Panel
var hovered_exam_item: String = ""

var drawer_pivot: Node3D
var hands_pivot: Node3D
var cheat_viewport: SubViewport
var cheat_mesh_inst: MeshInstance3D
var cheat_mat: StandardMaterial3D
var cheat_title_lbl: Label
var cheat_body_lbl: Label
var cheat_warn_lbl: Label

var teacher_root: Node3D
var teacher_back_group: Node3D
var teacher_front_sprite: Sprite3D
var teacher_chalk_arm: Node3D
var buzzer_mesh_mat: StandardMaterial3D
var classmate_arms: Array[Node3D] = []

# --- 2D HUD 節點參照 ---
var hud_layer: CanvasLayer
var title_panel: Control
var gameover_panel: Control
var gameover_title_lbl: Label
var gameover_sub_lbl: Label
var top_time_lbl: Label
var top_score_lbl: Label
var top_mode_badge: Panel
var top_mode_lbl: Label
var teacher_status_panel: Panel
var teacher_status_lbl: Label
var cam_dir_lbl: Label
var toast_panel: Panel
var toast_lbl: Label
var toast_timer: float = 0.0

var btn_switch_mode: Button
var btn_emg_hud: Button
var emg_bar: ProgressBar
var emg_bar_lbl: Label
var ecg_title_lbl: Label
var ecg_scope: Control
var btn_bpm_down: Button
var btn_bpm_up: Button
var btn_breathe: Button
var eeg_title_lbl: Label
var eeg_bar: ProgressBar
var eeg_clarity_lbl: Label
var btn_focus_down: Button
var btn_focus_up: Button
var guide_lbl: Label

func _ready() -> void:
	# 啟動 UDP 5005 外部訊號監聽
	var err: int = udp_server.bind(5005, "127.0.0.1")
	if err == OK:
		print("[Godot HardwareBridge] UDP 127.0.0.1:5005 外部訊號監聽已啟動")

	_build_3d_environment()
	_build_3d_classroom()
	_build_3d_classmates()
	_build_3d_teacher()
	_build_3d_player_desk_and_drawer()
	_build_2d_hud()
	_refresh_exam_paper_ui()
	_refresh_cheat_sheet_ui()
	_update_mode_ui()

# ==============================================================================
# 1. 建構 3D 燈光、環境與第一人稱相機
# ==============================================================================
func _build_3d_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.76, 0.82, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.92, 0.94, 0.96)
	env.ambient_light_energy = 0.85

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var dir_light := DirectionalLight3D.new()
	dir_light.rotation_degrees = Vector3(-50, -32, 0)
	dir_light.light_energy = 0.95
	dir_light.shadow_enabled = true
	add_child(dir_light)

	camera = Camera3D.new()
	camera.position = Vector3(0.0, 1.44, 0.42)
	camera.fov = 62.0
	camera.rotation = Vector3(cam_pitch, cam_yaw, 0.0)
	add_child(camera)

# ==============================================================================
# 2. 建構 3D 教室空間 (地板、牆面、窗戶、天花板日光燈、講台、黑板、蜂鳴器)
# ==============================================================================
func _make_box(pos: Vector3, sz: Vector3, col: Color, parent: Node3D = self, unshaded: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.85
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _build_3d_classroom() -> void:
	var room := Node3D.new()
	room.name = "ClassroomShell"
	add_child(room)

	# 地板與磁磚格線
	_make_box(Vector3(0, -0.05, -3.0), Vector3(8.2, 0.1, 9.2), Color(0.72, 0.65, 0.57), room)
	for gx in [-2.6, -1.3, 0.0, 1.3, 2.6]:
		_make_box(Vector3(gx, 0.002, -3.0), Vector3(0.03, 0.005, 9.0), Color(0.64, 0.57, 0.49), room)
	for gz in [-0.5, -1.8, -3.1, -4.4, -5.7]:
		_make_box(Vector3(0, 0.002, gz), Vector3(8.0, 0.005, 0.03), Color(0.64, 0.57, 0.49), room)

	# 天花板與發光日光燈管
	_make_box(Vector3(0, 3.3, -3.0), Vector3(8.2, 0.1, 9.2), Color(0.92, 0.94, 0.96), room)
	for lz in [-1.2, -3.4, -5.4]:
		for lx in [-1.6, 1.6]:
			_make_box(Vector3(lx, 3.23, lz), Vector3(1.1, 0.04, 0.32), Color(1.0, 1.0, 1.0), room, true)

	# 左牆與三扇明亮窗戶
	_make_box(Vector3(-4.0, 1.6, -3.0), Vector3(0.12, 3.3, 9.2), Color(0.84, 0.87, 0.90), room)
	for wz in [-1.2, -3.2, -5.2]:
		_make_box(Vector3(-3.92, 1.85, wz), Vector3(0.04, 1.45, 1.45), Color(0.45, 0.33, 0.22), room)
		_make_box(Vector3(-3.90, 1.95, wz), Vector3(0.04, 1.35, 1.35), Color(0.65, 0.86, 0.98), room, true)
		_make_box(Vector3(-3.89, 1.40, wz), Vector3(0.04, 0.42, 1.35), Color(0.45, 0.74, 0.50), room, true)

	# 右牆、木門與佈告欄
	_make_box(Vector3(4.0, 1.6, -3.0), Vector3(0.12, 3.3, 9.2), Color(0.82, 0.85, 0.88), room)
	_make_box(Vector3(3.92, 1.15, -5.5), Vector3(0.05, 2.3, 1.2), Color(0.53, 0.36, 0.22), room)
	_make_box(Vector3(3.92, 1.70, -2.2), Vector3(0.05, 1.25, 2.4), Color(0.25, 0.42, 0.33), room)

	# 前牆、講台木階梯與黑板
	_make_box(Vector3(0, 1.6, -7.2), Vector3(8.2, 3.3, 0.15), Color(0.87, 0.90, 0.92), room)
	_make_box(Vector3(0, 0.11, -6.3), Vector3(5.0, 0.22, 1.6), Color(0.64, 0.50, 0.37), room)

	# 黑板外框與黑板面
	_make_box(Vector3(0, 1.78, -7.10), Vector3(5.4, 1.68, 0.06), Color(0.44, 0.28, 0.15), room)
	_make_box(Vector3(0, 1.78, -7.06), Vector3(5.15, 1.48, 0.04), Color(0.13, 0.30, 0.22), room)

	# 黑板上的 3D 粉筆字
	var bb_lbl := Label3D.new()
	bb_lbl.text = "【生醫工程期末考】禁止偷看書桌抽屜小抄！違者零分當掉！\n移動滑鼠可自由轉頭：抬頭看奶龍 | 左右看鄰座同學 | 低頭看書桌考卷與抽屜"
	bb_lbl.font_size = 28
	bb_lbl.modulate = Color(0.92, 0.96, 0.92)
	bb_lbl.position = Vector3(-0.3, 2.15, -7.01)
	room.add_child(bb_lbl)

	# 黑板右上方 3D 蜂鳴器警示盒
	var buzz_box := _make_box(Vector3(2.05, 2.25, -7.02), Vector3(0.78, 0.32, 0.08), Color(0.22, 0.26, 0.28), room, true)
	buzzer_mesh_mat = buzz_box.material_override as StandardMaterial3D
	var buzz_lbl := Label3D.new()
	buzz_lbl.text = "蜂鳴器警報器"
	buzz_lbl.font_size = 24
	buzz_lbl.position = Vector3(2.05, 2.25, -6.96)
	room.add_child(buzz_lbl)

	# 講台上的老師講桌
	_make_box(Vector3(0, 0.62, -5.65), Vector3(1.45, 0.82, 0.45), Color(0.49, 0.32, 0.19), room)
	_make_box(Vector3(0, 1.04, -5.65), Vector3(1.55, 0.06, 0.55), Color(0.58, 0.40, 0.24), room)

# ==============================================================================
# 3. 建構旁邊與前排的其他學生 (3D 桌椅與動態考生)
# ==============================================================================
func _build_3d_classmates() -> void:
	var configs := [
		{"pos": Vector3(-1.50, 0, -0.45), "coat": Color(0.18, 0.45, 0.34), "hair": Color(0.11, 0.09, 0.08), "name": "左鄰座：阿明 (狂寫中)"},
		{"pos": Vector3( 1.50, 0, -0.45), "coat": Color(0.27, 0.32, 0.46), "hair": Color(0.16, 0.12, 0.09), "name": "右鄰座：小華 (苦思抓頭)"},
		{"pos": Vector3(-2.15, 0, -2.35), "coat": Color(0.55, 0.27, 0.25), "hair": Color(0.10, 0.09, 0.08), "name": ""},
		{"pos": Vector3(-0.95, 0, -2.45), "coat": Color(0.24, 0.37, 0.51), "hair": Color(0.14, 0.11, 0.09), "name": ""},
		{"pos": Vector3( 0.95, 0, -2.45), "coat": Color(0.48, 0.38, 0.25), "hair": Color(0.12, 0.10, 0.08), "name": ""},
		{"pos": Vector3( 2.15, 0, -2.35), "coat": Color(0.33, 0.43, 0.35), "hair": Color(0.10, 0.09, 0.07), "name": ""},
		{"pos": Vector3(-1.35, 0, -4.30), "coat": Color(0.22, 0.35, 0.39), "hair": Color(0.09, 0.08, 0.07), "name": ""},
		{"pos": Vector3( 1.35, 0, -4.30), "coat": Color(0.37, 0.28, 0.40), "hair": Color(0.15, 0.11, 0.09), "name": ""}
	]

	for cfg in configs:
		var st_root := Node3D.new()
		st_root.position = cfg["pos"]
		add_child(st_root)

		# 學生書桌與桌面白色考卷
		_make_box(Vector3(0, 0.64, -0.35), Vector3(0.88, 0.18, 0.52), Color(0.56, 0.42, 0.29), st_root)
		_make_box(Vector3(0, 0.74, -0.35), Vector3(0.92, 0.04, 0.56), Color(0.74, 0.58, 0.42), st_root)
		_make_box(Vector3(-0.40, 0.36, -0.35), Vector3(0.05, 0.72, 0.46), Color(0.43, 0.33, 0.24), st_root)
		_make_box(Vector3( 0.40, 0.36, -0.35), Vector3(0.05, 0.72, 0.46), Color(0.43, 0.33, 0.24), st_root)
		_make_box(Vector3(0, 0.765, -0.34), Vector3(0.46, 0.005, 0.34), Color(0.97, 0.97, 0.95), st_root)

		# 學生軀幹與椅子
		_make_box(Vector3(0, 0.58, 0.18), Vector3(0.44, 0.48, 0.05), Color(0.37, 0.27, 0.19), st_root)
		_make_box(Vector3(0, 0.78, 0.0), Vector3(0.42, 0.56, 0.24), cfg["coat"], st_root)

		# 學生 3D 頭部球體
		var head_mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.145
		sm.height = 0.29
		head_mi.mesh = sm
		var hmat := StandardMaterial3D.new()
		hmat.albedo_color = cfg["hair"]
		head_mi.material_override = hmat
		head_mi.position = Vector3(0, 1.21, -0.02)
		st_root.add_child(head_mi)

		# 伸到書桌上寫字的手臂
		var arm_pivot := Node3D.new()
		arm_pivot.position = Vector3(0.18, 0.78, -0.08)
		st_root.add_child(arm_pivot)
		_make_box(Vector3(0, 0, -0.14), Vector3(0.10, 0.08, 0.30), cfg["coat"], arm_pivot)
		classmate_arms.append(arm_pivot)

		if cfg["name"] != "":
			var nlbl := Label3D.new()
			nlbl.text = cfg["name"]
			nlbl.font_size = 22
			nlbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			nlbl.modulate = Color(1.0, 0.96, 0.82)
			nlbl.position = Vector3(0, 1.48, 0)
			st_root.add_child(nlbl)

# ==============================================================================
# 4. 建構 3D 奶龍監考官 (背對寫板書 3D 模型 + 正面巡邏 Sprite3D 貼圖)
# ==============================================================================
func _build_3d_teacher() -> void:
	teacher_root = Node3D.new()
	teacher_root.position = Vector3(0, 0.22, -6.2)
	add_child(teacher_root)

	# 背對寫板書群組
	teacher_back_group = Node3D.new()
	teacher_root.add_child(teacher_back_group)

	var body_mi := MeshInstance3D.new()
	var body_sm := SphereMesh.new()
	body_sm.radius = 0.45
	body_sm.height = 1.15
	body_mi.mesh = body_sm
	var y_mat := StandardMaterial3D.new()
	y_mat.albedo_color = Color(0.97, 0.79, 0.23)
	body_mi.material_override = y_mat
	body_mi.position = Vector3(0, 0.78, 0)
	teacher_back_group.add_child(body_mi)

	_make_box(Vector3(-0.18, 0.18, 0), Vector3(0.18, 0.36, 0.18), Color(0.90, 0.72, 0.18), teacher_back_group)
	_make_box(Vector3( 0.18, 0.18, 0), Vector3(0.18, 0.36, 0.18), Color(0.90, 0.72, 0.18), teacher_back_group)

	teacher_chalk_arm = Node3D.new()
	teacher_chalk_arm.position = Vector3(0.42, 0.95, 0)
	teacher_back_group.add_child(teacher_chalk_arm)
	_make_box(Vector3(0.08, 0.08, 0), Vector3(0.14, 0.14, 0.14), Color(0.33, 0.29, 0.25), teacher_chalk_arm)
	_make_box(Vector3(0.14, 0.16, 0), Vector3(0.03, 0.14, 0.03), Color(1, 1, 1), teacher_chalk_arm, true)

	# 正面巡邏：載入經典奶龍迷因貼圖 (nailong.png)
	teacher_front_sprite = Sprite3D.new()
	if ResourceLoader.exists("res://nailong.png"):
		teacher_front_sprite.texture = load("res://nailong.png")
	teacher_front_sprite.pixel_size = 0.0032
	teacher_front_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	teacher_front_sprite.position = Vector3(0, 0.78, 0)
	teacher_front_sprite.visible = false
	teacher_root.add_child(teacher_front_sprite)

	var t_lbl := Label3D.new()
	t_lbl.text = "★ 監考官：奶龍教授"
	t_lbl.font_size = 24
	t_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	t_lbl.modulate = Color(1.0, 0.94, 0.65)
	t_lbl.position = Vector3(0, 1.52, 0)
	teacher_root.add_child(t_lbl)

# ==============================================================================
# 5. 建構玩家書桌、3D 書桌平面考卷 (SubViewport) 與抽屜伸手翻小抄模型
# ==============================================================================
func _build_3d_player_desk_and_drawer() -> void:
	var desk_root := Node3D.new()
	desk_root.name = "PlayerDesk"
	add_child(desk_root)

	# 書桌桌面 (微傾設計讓桌面考卷在 3D 視角下極度清晰且完全平貼桌面)
	var desk_top := _make_box(Vector3(0, 0.79, -0.66), Vector3(1.28, 0.04, 0.66), Color(0.77, 0.60, 0.42), desk_root)
	desk_top.rotation_degrees = Vector3(12.0, 0, 0)

	# 書桌左右桌腳與後擋板
	_make_box(Vector3(-0.58, 0.38, -0.66), Vector3(0.06, 0.76, 0.60), Color(0.45, 0.32, 0.21), desk_root)
	_make_box(Vector3( 0.58, 0.38, -0.66), Vector3(0.06, 0.76, 0.60), Color(0.45, 0.32, 0.21), desk_root)

	# 桌角原子筆與橡皮擦
	var pen := _make_box(Vector3(0.49, 0.81, -0.60), Vector3(0.02, 0.015, 0.28), Color(0.18, 0.38, 0.75), desk_root)
	pen.rotation_degrees = Vector3(12.0, -8.0, 0)
	var eraser := _make_box(Vector3(0.52, 0.76, -0.42), Vector3(0.06, 0.02, 0.04), Color(0.96, 0.96, 0.98), desk_root)
	eraser.rotation_degrees = Vector3(12.0, 0, 0)

	# ---------------- A. 書桌平面上的 3D 考卷 (SubViewport -> QuadMesh) ----------------
	exam_viewport = SubViewport.new()
	exam_viewport.size = Vector2i(760, 500)
	exam_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(exam_viewport)

	var paper_bg := Panel.new()
	paper_bg.size = Vector2(760, 500)
	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.99, 0.98, 0.95)
	p_style.border_color = Color(0.75, 0.73, 0.68)
	p_style.set_border_width_all(4)
	paper_bg.add_theme_stylebox_override("panel", p_style)
	exam_viewport.add_child(paper_bg)

	exam_header_label = Label.new()
	exam_header_label.position = Vector2(24, 14)
	exam_header_label.add_theme_font_size_override("font_size", 22)
	exam_header_label.add_theme_color_override("font_color", Color(0.12, 0.43, 0.68))
	paper_bg.add_child(exam_header_label)

	# 考卷右上角：< 上一題 / 下一題 > / ★ 提早交卷
	exam_btn_prev = _make_paper_nav_btn(paper_bg, Rect2(390, 12, 105, 36), "< 上一題", Color(0.90, 0.93, 0.97), Color(0.15, 0.15, 0.15))
	exam_btn_next = _make_paper_nav_btn(paper_bg, Rect2(505, 12, 105, 36), "下一題 >", Color(0.90, 0.93, 0.97), Color(0.15, 0.15, 0.15))
	exam_btn_submit = _make_paper_nav_btn(paper_bg, Rect2(620, 12, 116, 36), "★ 提早交卷", Color(0.18, 0.80, 0.44), Color(1, 1, 1))

	# 考卷題幹文字 (啟用 AUTOWRAP_WORD_SMART 自動換行，絕不截斷！)
	exam_q_label = Label.new()
	exam_q_label.position = Vector2(24, 62)
	exam_q_label.size = Vector2(712, 125)
	exam_q_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	exam_q_label.add_theme_font_size_override("font_size", 24)
	exam_q_label.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08))
	paper_bg.add_child(exam_q_label)

	# 4 個選項按鈕框 (平鋪於考卷平面內)
	for i in range(4):
		var op_panel := Panel.new()
		op_panel.position = Vector2(24, 198 + i * 70)
		op_panel.size = Vector2(712, 58)
		paper_bg.add_child(op_panel)
		exam_opt_panels.append(op_panel)

		var op_lbl := Label.new()
		op_lbl.position = Vector2(18, 12)
		op_lbl.size = Vector2(680, 36)
		op_lbl.add_theme_font_size_override("font_size", 22)
		op_lbl.add_theme_color_override("font_color", Color(0.10, 0.10, 0.10))
		op_panel.add_child(op_lbl)
		exam_opt_labels.append(op_lbl)

	# 將考卷 SubViewport 貼在 3D 書桌平面上
	exam_mesh_inst = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.88, 0.58)
	exam_mesh_inst.mesh = qm
	var emat := StandardMaterial3D.new()
	emat.albedo_texture = exam_viewport.get_texture()
	emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	exam_mesh_inst.material_override = emat
	exam_mesh_inst.position = Vector3(-0.02, 0.816, -0.66)
	exam_mesh_inst.rotation_degrees = Vector3(-78.0, 0, 0)
	desk_root.add_child(exam_mesh_inst)

	# ---------------- B. 書桌下方的立體抽屜與抽屜內小抄 ----------------
	drawer_pivot = Node3D.new()
	drawer_pivot.position = Vector3(0, 0.58, -0.64)
	desk_root.add_child(drawer_pivot)

	# 抽屜底板、左右側板、前擋板與金屬把手
	_make_box(Vector3(0, 0.0, 0.0), Vector3(0.88, 0.02, 0.46), Color(0.29, 0.20, 0.13), drawer_pivot)
	_make_box(Vector3(-0.44, 0.06, 0.0), Vector3(0.03, 0.12, 0.46), Color(0.46, 0.33, 0.21), drawer_pivot)
	_make_box(Vector3( 0.44, 0.06, 0.0), Vector3(0.03, 0.12, 0.46), Color(0.46, 0.33, 0.21), drawer_pivot)
	_make_box(Vector3(0, 0.05, 0.23), Vector3(0.90, 0.11, 0.03), Color(0.53, 0.38, 0.24), drawer_pivot)
	_make_box(Vector3(0, 0.05, 0.25), Vector3(0.16, 0.025, 0.02), Color(0.85, 0.74, 0.41), drawer_pivot)
	# 抽屜內的藍色課本
	_make_box(Vector3(-0.30, 0.02, 0.05), Vector3(0.18, 0.025, 0.26), Color(0.22, 0.45, 0.65), drawer_pivot)

	# 抽屜裡的小抄 SubViewport
	cheat_viewport = SubViewport.new()
	cheat_viewport.size = Vector2i(620, 250)
	cheat_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(cheat_viewport)

	var c_bg := Panel.new()
	c_bg.size = Vector2(620, 250)
	var c_style := StyleBoxFlat.new()
	c_style.bg_color = Color(1.0, 0.97, 0.75)
	c_style.border_color = Color(0.76, 0.63, 0.25)
	c_style.set_border_width_all(4)
	c_bg.add_theme_stylebox_override("panel", c_style)
	cheat_viewport.add_child(c_bg)

	cheat_title_lbl = Label.new()
	cheat_title_lbl.position = Vector2(18, 10)
	cheat_title_lbl.add_theme_font_size_override("font_size", 19)
	cheat_title_lbl.add_theme_color_override("font_color", Color(0.58, 0.30, 0.04))
	c_bg.add_child(cheat_title_lbl)

	cheat_body_lbl = Label.new()
	cheat_body_lbl.position = Vector2(18, 48)
	cheat_body_lbl.size = Vector2(584, 140)
	cheat_body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cheat_body_lbl.add_theme_font_size_override("font_size", 25)
	cheat_body_lbl.add_theme_color_override("font_color", Color(0.78, 0.08, 0.08))
	c_bg.add_child(cheat_body_lbl)

	cheat_warn_lbl = Label.new()
	cheat_warn_lbl.position = Vector2(18, 205)
	cheat_warn_lbl.text = "▲ 腦波不專注！抽屜裡的小抄字體幾乎完全透明！"
	cheat_warn_lbl.add_theme_font_size_override("font_size", 18)
	cheat_warn_lbl.add_theme_color_override("font_color", Color(0.85, 0.15, 0.15))
	c_bg.add_child(cheat_warn_lbl)

	cheat_mesh_inst = MeshInstance3D.new()
	var cqm := QuadMesh.new()
	cqm.size = Vector2(0.56, 0.23)
	cheat_mesh_inst.mesh = cqm
	cheat_mat = StandardMaterial3D.new()
	cheat_mat.albedo_texture = cheat_viewport.get_texture()
	cheat_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cheat_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cheat_mesh_inst.material_override = cheat_mat
	cheat_mesh_inst.position = Vector3(0.05, 0.05, 0.08)
	cheat_mesh_inst.rotation_degrees = Vector3(-62.0, 0, 0)
	drawer_pivot.add_child(cheat_mesh_inst)

	# ---------------- C. 玩家伸入抽屜打開小抄的 3D 雙手模型 ----------------
	hands_pivot = Node3D.new()
	hands_pivot.position = Vector3(0.0, 0.42, 0.15)
	desk_root.add_child(hands_pivot)

	# 左手臂與手掌
	_make_box(Vector3(-0.20, -0.06, 0.18), Vector3(0.11, 0.09, 0.34), Color(0.16, 0.22, 0.31), hands_pivot)
	_make_box(Vector3(-0.20, -0.02, 0.0), Vector3(0.10, 0.05, 0.12), Color(0.95, 0.78, 0.66), hands_pivot)
	# 右手臂與手掌
	_make_box(Vector3( 0.24, -0.06, 0.18), Vector3(0.11, 0.09, 0.34), Color(0.16, 0.22, 0.31), hands_pivot)
	_make_box(Vector3( 0.24, -0.02, 0.0), Vector3(0.10, 0.05, 0.12), Color(0.95, 0.78, 0.66), hands_pivot)

func _make_paper_nav_btn(parent: Control, rect: Rect2, txt: String, bg_col: Color, fg_col: Color) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	var st := StyleBoxFlat.new()
	st.bg_color = bg_col
	st.border_color = Color(0.55, 0.60, 0.68)
	st.set_border_width_all(2)
	st.set_corner_radius_all(5)
	p.add_theme_stylebox_override("panel", st)
	parent.add_child(p)

	var l := Label.new()
	l.text = txt
	l.size = rect.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", fg_col)
	p.add_child(l)
	return p

# ==============================================================================
# 6. 建構 2D 生醫監控 HUD、首頁雙模式選單與結算畫面
# ==============================================================================
func _build_2d_hud() -> void:
	hud_layer = CanvasLayer.new()
	add_child(hud_layer)

	# 頂部狀態列
	var top_bar := Panel.new()
	top_bar.size = Vector2(1280, 42)
	var tb_st := StyleBoxFlat.new()
	tb_st.bg_color = Color(0.11, 0.16, 0.21)
	top_bar.add_theme_stylebox_override("panel", tb_st)
	hud_layer.add_child(top_bar)

	var t_title := Label.new()
	t_title.text = "NeuroCheat 3D (Godot 4)：生醫工程期末考"
	t_title.position = Vector2(16, 7)
	t_title.add_theme_font_size_override("font_size", 20)
	top_bar.add_child(t_title)

	top_mode_badge = Panel.new()
	top_mode_badge.position = Vector2(410, 7)
	top_mode_badge.size = Vector2(195, 28)
	top_bar.add_child(top_mode_badge)

	top_mode_lbl = Label.new()
	top_mode_lbl.size = Vector2(195, 28)
	top_mode_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_mode_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_mode_lbl.add_theme_font_size_override("font_size", 14)
	top_mode_badge.add_child(top_mode_lbl)

	top_time_lbl = Label.new()
	top_time_lbl.position = Vector2(630, 7)
	top_time_lbl.add_theme_font_size_override("font_size", 20)
	top_bar.add_child(top_time_lbl)

	top_score_lbl = Label.new()
	top_score_lbl.position = Vector2(910, 8)
	top_score_lbl.add_theme_font_size_override("font_size", 18)
	top_score_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	top_bar.add_child(top_score_lbl)

	# 左上角：奶龍動態警戒列 & 3D 視角方位提示
	teacher_status_panel = Panel.new()
	teacher_status_panel.position = Vector2(14, 48)
	teacher_status_panel.size = Vector2(865, 34)
	hud_layer.add_child(teacher_status_panel)

	teacher_status_lbl = Label.new()
	teacher_status_lbl.position = Vector2(12, 4)
	teacher_status_lbl.add_theme_font_size_override("font_size", 18)
	teacher_status_panel.add_child(teacher_status_lbl)

	var cam_panel := Panel.new()
	cam_panel.position = Vector2(14, 86)
	cam_panel.size = Vector2(460, 26)
	var cp_st := StyleBoxFlat.new()
	cp_st.bg_color = Color(0.12, 0.16, 0.21, 0.88)
	cp_st.border_color = Color(0.35, 0.58, 0.82)
	cp_st.set_border_width_all(1)
	cp_st.set_corner_radius_all(4)
	cam_panel.add_theme_stylebox_override("panel", cp_st)
	hud_layer.add_child(cam_panel)

	cam_dir_lbl = Label.new()
	cam_dir_lbl.position = Vector2(10, 2)
	cam_dir_lbl.add_theme_font_size_override("font_size", 14)
	cam_dir_lbl.add_theme_color_override("font_color", Color(0.75, 0.90, 1.0))
	cam_panel.add_child(cam_dir_lbl)

	# 動態操作反饋橫幅 (Toast)
	toast_panel = Panel.new()
	toast_panel.position = Vector2(180, 118)
	toast_panel.size = Vector2(520, 38)
	toast_panel.visible = false
	var tst := StyleBoxFlat.new()
	tst.bg_color = Color(0.08, 0.12, 0.18, 0.92)
	tst.border_color = Color(0.18, 0.80, 0.44)
	tst.set_border_width_all(2)
	tst.set_corner_radius_all(6)
	toast_panel.add_theme_stylebox_override("panel", tst)
	hud_layer.add_child(toast_panel)

	toast_lbl = Label.new()
	toast_lbl.size = Vector2(520, 38)
	toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_lbl.add_theme_font_size_override("font_size", 18)
	toast_panel.add_child(toast_lbl)

	# 右側生醫生理訊號監控儀表板
	var dash := Panel.new()
	dash.position = Vector2(895, 48)
	dash.size = Vector2(375, 655)
	var d_st := StyleBoxFlat.new()
	d_st.bg_color = Color(0.08, 0.10, 0.14, 0.93)
	d_st.border_color = Color(0.25, 0.33, 0.43)
	d_st.set_border_width_all(2)
	d_st.set_corner_radius_all(8)
	dash.add_theme_stylebox_override("panel", d_st)
	hud_layer.add_child(dash)

	var d_title := Label.new()
	d_title.text = "★ 生醫生理訊號監控儀 (Godot HUD)"
	d_title.position = Vector2(14, 10)
	d_title.add_theme_font_size_override("font_size", 19)
	d_title.add_theme_color_override("font_color", Color(0.4, 0.82, 1.0))
	dash.add_child(d_title)

	btn_switch_mode = Button.new()
	btn_switch_mode.position = Vector2(14, 40)
	btn_switch_mode.size = Vector2(347, 30)
	btn_switch_mode.pressed.connect(_on_switch_mode_pressed)
	dash.add_child(btn_switch_mode)

	# 1. EMG
	var emg_lbl := Label.new()
	emg_lbl.text = "1. EMG 肌電 [伸手拉開抽屜看小抄]"
	emg_lbl.position = Vector2(14, 80)
	emg_lbl.add_theme_font_size_override("font_size", 17)
	dash.add_child(emg_lbl)

	btn_emg_hud = Button.new()
	btn_emg_hud.position = Vector2(14, 106)
	btn_emg_hud.size = Vector2(347, 40)
	btn_emg_hud.pressed.connect(toggle_emg)
	dash.add_child(btn_emg_hud)

	emg_bar = ProgressBar.new()
	emg_bar.position = Vector2(14, 152)
	emg_bar.size = Vector2(347, 22)
	emg_bar.max_value = 100.0
	emg_bar.show_percentage = false
	dash.add_child(emg_bar)

	emg_bar_lbl = Label.new()
	emg_bar_lbl.position = Vector2(22, 152)
	emg_bar_lbl.add_theme_font_size_override("font_size", 14)
	dash.add_child(emg_bar_lbl)

	# 2. ECG
	ecg_title_lbl = Label.new()
	ecg_title_lbl.position = Vector2(14, 186)
	ecg_title_lbl.add_theme_font_size_override("font_size", 17)
	dash.add_child(ecg_title_lbl)

	ecg_scope = ECGScopeScript.new()
	ecg_scope.position = Vector2(14, 212)
	ecg_scope.size = Vector2(347, 82)
	dash.add_child(ecg_scope)

	btn_bpm_down = Button.new()
	btn_bpm_down.position = Vector2(14, 300)
	btn_bpm_down.size = Vector2(96, 32)
	btn_bpm_down.pressed.connect(func(): _adjust_bpm(-5.0))
	dash.add_child(btn_bpm_down)

	btn_bpm_up = Button.new()
	btn_bpm_up.position = Vector2(116, 300)
	btn_bpm_up.size = Vector2(96, 32)
	btn_bpm_up.pressed.connect(func(): _adjust_bpm(5.0))
	dash.add_child(btn_bpm_up)

	btn_breathe = Button.new()
	btn_breathe.position = Vector2(218, 300)
	btn_breathe.size = Vector2(143, 32)
	btn_breathe.button_down.connect(func(): _set_breathe(true))
	btn_breathe.button_up.connect(func(): _set_breathe(false))
	dash.add_child(btn_breathe)

	# 3. EEG
	eeg_title_lbl = Label.new()
	eeg_title_lbl.position = Vector2(14, 344)
	eeg_title_lbl.add_theme_font_size_override("font_size", 17)
	dash.add_child(eeg_title_lbl)

	eeg_bar = ProgressBar.new()
	eeg_bar.position = Vector2(14, 370)
	eeg_bar.size = Vector2(347, 26)
	eeg_bar.max_value = 100.0
	eeg_bar.show_percentage = false
	dash.add_child(eeg_bar)

	eeg_clarity_lbl = Label.new()
	eeg_clarity_lbl.position = Vector2(22, 372)
	eeg_clarity_lbl.add_theme_font_size_override("font_size", 14)
	dash.add_child(eeg_clarity_lbl)

	btn_focus_down = Button.new()
	btn_focus_down.position = Vector2(14, 402)
	btn_focus_down.size = Vector2(168, 32)
	btn_focus_down.pressed.connect(func(): _adjust_focus(-10.0))
	dash.add_child(btn_focus_down)

	btn_focus_up = Button.new()
	btn_focus_up.position = Vector2(193, 402)
	btn_focus_up.size = Vector2(168, 32)
	btn_focus_up.pressed.connect(func(): _adjust_focus(10.0))
	dash.add_child(btn_focus_up)

	# 4. 操作指南面板
	var g_box := Panel.new()
	g_box.position = Vector2(14, 444)
	g_box.size = Vector2(347, 198)
	var g_st := StyleBoxFlat.new()
	g_st.bg_color = Color(0.11, 0.13, 0.17)
	g_st.set_corner_radius_all(6)
	g_box.add_theme_stylebox_override("panel", g_st)
	dash.add_child(g_box)

	guide_lbl = Label.new()
	guide_lbl.position = Vector2(10, 8)
	guide_lbl.size = Vector2(328, 182)
	guide_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_lbl.add_theme_font_size_override("font_size", 14)
	guide_lbl.add_theme_color_override("font_color", Color(0.82, 0.88, 0.94))
	g_box.add_child(guide_lbl)

	# ---------------- 首頁雙模式選擇覆蓋層 ----------------
	_build_title_overlay()
	# ---------------- 結算覆蓋層 ----------------
	_build_gameover_overlay()

func _build_title_overlay() -> void:
	title_panel = Panel.new()
	title_panel.size = Vector2(1280, 720)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.11, 0.16, 0.96)
	title_panel.add_theme_stylebox_override("panel", st)
	hud_layer.add_child(title_panel)

	var t_main := Label.new()
	t_main.text = "NeuroCheat 3D (Godot 4 Engine)"
	t_main.size = Vector2(1280, 60)
	t_main.position = Vector2(0, 55)
	t_main.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t_main.add_theme_font_size_override("font_size", 42)
	title_panel.add_child(t_main)

	var t_sub := Label.new()
	t_sub.text = "生醫工程期末專題 Group 6 — B13502162 黃建澄 • B13901094 王家佑 • B13901135 張嘉宸\n3D 教室滑鼠自由視角 | 書桌平面透視考卷 | 伸手拉開抽屜看小抄 | 奶龍監考官 AI"
	t_sub.size = Vector2(1280, 70)
	t_sub.position = Vector2(0, 120)
	t_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t_sub.add_theme_font_size_override("font_size", 20)
	t_sub.add_theme_color_override("font_color", Color(0.55, 0.82, 1.0))
	title_panel.add_child(t_sub)

	var btn_m1 := Button.new()
	btn_m1.position = Vector2(120, 240)
	btn_m1.size = Vector2(490, 260)
	btn_m1.text = "【模式一：手動調控模式】\n(按 1 鍵 / 空白鍵 / 點此開始)\n\n• 玩家自行控制 ECG(↑/↓)、EEG(W/S) 與 EMG(空白鍵)\n• 移動滑鼠可抬頭看奶龍、左右看同學、低頭看書桌考卷\n• 按空白鍵伸出 3D 雙手拉開書桌抽屜翻閱小抄"
	btn_m1.add_theme_font_size_override("font_size", 19)
	btn_m1.pressed.connect(func(): _start_game(BioMode.MANUAL))
	title_panel.add_child(btn_m1)

	var btn_m2 := Button.new()
	btn_m2.position = Vector2(670, 240)
	btn_m2.size = Vector2(490, 260)
	btn_m2.text = "【模式二：外部訊號輸入模式】\n(按 2 鍵 / 點此開始)\n\n• 鎖定手動 ECG 與 EEG 調整，必須由外部輸入生理訊號！\n• 內建 UDP 127.0.0.1:5005 與 JSON 即時接收器\n• 可直接使用 external_signal_sender.py 或 Arduino 串流\n• 抽屜小抄開闔 (EMG) 維持以空白鍵/滑鼠右鍵/按鈕控制"
	btn_m2.add_theme_font_size_override("font_size", 19)
	btn_m2.pressed.connect(func(): _start_game(BioMode.EXTERNAL))
	title_panel.add_child(btn_m2)

	var hint_bot := Label.new()
	hint_bot.text = "★ 過關條件：120 秒內於書桌考卷取得 90 分以上 (A+) 即可過關，寫完可點考卷右上角【★ 提早交卷】！"
	hint_bot.size = Vector2(1280, 40)
	hint_bot.position = Vector2(0, 550)
	hint_bot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_bot.add_theme_font_size_override("font_size", 21)
	hint_bot.add_theme_color_override("font_color", Color(1.0, 0.78, 0.25))
	title_panel.add_child(hint_bot)

func _build_gameover_overlay() -> void:
	gameover_panel = Panel.new()
	gameover_panel.size = Vector2(1280, 720)
	gameover_panel.visible = false
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.04, 0.06, 0.09, 0.88)
	gameover_panel.add_theme_stylebox_override("panel", st)
	hud_layer.add_child(gameover_panel)

	gameover_title_lbl = Label.new()
	gameover_title_lbl.size = Vector2(1280, 60)
	gameover_title_lbl.position = Vector2(0, 180)
	gameover_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gameover_title_lbl.add_theme_font_size_override("font_size", 38)
	gameover_panel.add_child(gameover_title_lbl)

	gameover_sub_lbl = Label.new()
	gameover_sub_lbl.size = Vector2(1280, 100)
	gameover_sub_lbl.position = Vector2(0, 260)
	gameover_sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gameover_sub_lbl.add_theme_font_size_override("font_size", 22)
	gameover_panel.add_child(gameover_sub_lbl)

	var btn_retry := Button.new()
	btn_retry.position = Vector2(410, 410)
	btn_retry.size = Vector2(220, 56)
	btn_retry.text = "重新挑戰 (空白鍵)"
	btn_retry.add_theme_font_size_override("font_size", 20)
	btn_retry.pressed.connect(func(): _start_game(bio_mode))
	gameover_panel.add_child(btn_retry)

	var btn_menu := Button.new()
	btn_menu.position = Vector2(650, 410)
	btn_menu.size = Vector2(220, 56)
	btn_menu.text = "回模式選單 (ESC)"
	btn_menu.add_theme_font_size_override("font_size", 20)
	btn_menu.pressed.connect(func():
		game_state = GameState.TITLE
		title_panel.visible = true
		gameover_panel.visible = false
	)
	gameover_panel.add_child(btn_menu)

# ==============================================================================
# 7. 遊戲主迴圈與 3D 互動更新 (_process & _input)
# ==============================================================================
func _start_game(selected_mode: BioMode) -> void:
	bio_mode = selected_mode
	game_state = GameState.PLAYING
	title_panel.visible = false
	gameover_panel.visible = false

	time_left = 120.0
	current_q_idx = 0
	for q in questions:
		q["user_ans"] = -1

	emg_active = false
	emg_level = 0.0
	base_bpm = 72.0
	ecg_bpm = 72.0
	eeg_focus = 75.0
	eeg_target_focus = 75.0
	is_deep_breathing = false

	teacher_state = TeacherState.WRITING_BOARD
	teacher_timer = 5.5
	patrol_progress = 0.0
	buzzer_active = false
	facing_player = false

	_refresh_exam_paper_ui()
	_refresh_cheat_sheet_ui()
	_update_mode_ui()
	_show_toast("★ 考試正式開始！移動滑鼠可轉動 3D 視角，按空白鍵伸手拉開抽屜看小抄！")

func _on_switch_mode_pressed() -> void:
	if bio_mode == BioMode.MANUAL:
		bio_mode = BioMode.EXTERNAL
		_show_toast("★ 已切換為【模式二：外部訊號模式】！請由外部輸入 ECG 與 EEG")
	else:
		bio_mode = BioMode.MANUAL
		_show_toast("★ 已切換為【模式一：手動調控模式】！可自行調控 ECG、EEG、EMG")
	_update_mode_ui()

func toggle_emg() -> void:
	if game_state != GameState.PLAYING:
		return
	emg_active = not emg_active
	if emg_active:
		_show_toast("🖐️ 已伸手拉開書桌抽屜並攤開小抄！")
	else:
		_show_toast("📥 已將小抄折好並推回書桌抽屜！")
	_update_mode_ui()

func _adjust_bpm(delta: float) -> void:
	if bio_mode == BioMode.EXTERNAL:
		_show_toast("🔒 目前為【外部訊號模式】，必須從外部輸入 ECG/EEG！(按 M 可切換手動)")
		return
	base_bpm = clampf(base_bpm + delta, 45.0, 170.0)
	ecg_bpm = clampf(ecg_bpm + delta, 45.0, 170.0)
	_show_toast("💓 ECG 心率調整為：%.0f BPM" % ecg_bpm)

func _adjust_focus(delta: float) -> void:
	if bio_mode == BioMode.EXTERNAL:
		_show_toast("🔒 目前為【外部訊號模式】，必須從外部輸入 ECG/EEG！(按 M 可切換手動)")
		return
	eeg_target_focus = clampf(eeg_target_focus + delta, 5.0, 100.0)
	eeg_focus = eeg_target_focus
	_refresh_cheat_sheet_ui()
	_show_toast("🧠 EEG 專注度調整為：%.0f%%" % eeg_focus)

func _set_breathe(active: bool) -> void:
	if bio_mode == BioMode.EXTERNAL and active:
		_show_toast("🔒 目前為【外部訊號模式】，必須從外部輸入 ECG/EEG！")
		is_deep_breathing = false
		return
	is_deep_breathing = active

func _show_toast(msg: String) -> void:
	toast_lbl.text = msg
	toast_panel.visible = true
	toast_timer = 1.6

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if game_state == GameState.TITLE:
			if k.keycode in [KEY_1, KEY_KP_1, KEY_SPACE, KEY_ENTER]:
				_start_game(BioMode.MANUAL)
			elif k.keycode in [KEY_2, KEY_KP_2]:
				_start_game(BioMode.EXTERNAL)
			return

		if game_state != GameState.PLAYING:
			if k.keycode == KEY_ESCAPE:
				game_state = GameState.TITLE
				title_panel.visible = true
				gameover_panel.visible = false
			elif k.keycode in [KEY_SPACE, KEY_ENTER]:
				_start_game(bio_mode)
			return

		# PLAYING 狀態快捷鍵
		match k.keycode:
			KEY_ESCAPE:
				game_state = GameState.TITLE
				title_panel.visible = true
			KEY_M:
				_on_switch_mode_pressed()
			KEY_SPACE, KEY_C, KEY_E:
				toggle_emg()
			KEY_UP:
				_adjust_bpm(5.0)
			KEY_DOWN:
				_adjust_bpm(-5.0)
			KEY_W:
				_adjust_focus(10.0)
			KEY_S:
				_adjust_focus(-10.0)
			KEY_R:
				_set_breathe(true)
			KEY_1, KEY_KP_1, KEY_A:
				_select_answer(0)
			KEY_2, KEY_KP_2, KEY_B:
				_select_answer(1)
			KEY_3, KEY_KP_3:
				_select_answer(2)
			KEY_4, KEY_KP_4, KEY_D:
				_select_answer(3)
			KEY_LEFT:
				_change_question(-1)
			KEY_RIGHT:
				_change_question(1)

	elif event is InputEventKey and not event.pressed:
		if (event as InputEventKey).keycode == KEY_R:
			_set_breathe(false)

	elif event is InputEventMouseButton and event.pressed and game_state == GameState.PLAYING:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			toggle_emg()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.position.x < 890:
			# 3D 桌面考卷射線點擊判定
			var hit_item := _raycast_desk_paper_uv(mb.position)
			if hit_item.begins_with("OPT_"):
				var idx := int(hit_item.substr(4, 1))
				_select_answer(idx)
			elif hit_item == "PREV":
				_change_question(-1)
			elif hit_item == "NEXT":
				_change_question(1)
			elif hit_item == "SUBMIT":
				_submit_exam_early()

func _raycast_desk_paper_uv(screen_pos: Vector2) -> String:
	if screen_pos.x >= 890:
		return ""
	var ray_orig := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var plane_norm := exam_mesh_inst.global_transform.basis.z.normalized()
	var plane := Plane(plane_norm, exam_mesh_inst.global_position)
	var hit = plane.intersects_ray(ray_orig, ray_dir)
	if hit == null:
		return ""
	var local_pt := exam_mesh_inst.to_local(hit)
	# QuadMesh 尺寸為 (0.88, 0.58)
	var u := (local_pt.x / 0.88 + 0.5) * 760.0
	var v := (0.5 - local_pt.y / 0.58) * 500.0
	if u < 0.0 or u > 760.0 or v < 0.0 or v > 500.0:
		return ""

	var uv := Vector2(u, v)
	if Rect2(390, 12, 105, 36).has_point(uv):
		return "PREV"
	if Rect2(505, 12, 105, 36).has_point(uv):
		return "NEXT"
	if Rect2(620, 12, 116, 36).has_point(uv):
		return "SUBMIT"
	for i in range(4):
		if Rect2(24, 198 + i * 70, 712, 58).has_point(uv):
			return "OPT_%d" % i
	return ""

func _select_answer(idx: int) -> void:
	questions[current_q_idx]["user_ans"] = idx
	_refresh_exam_paper_ui()
	var let: String = ["A", "B", "C", "D"][idx]
	_show_toast("✏️ 第 %d 題已選擇答案 [%s]" % [current_q_idx + 1, let])

func _change_question(step: int) -> void:
	var nxt := clampi(current_q_idx + step, 0, questions.size() - 1)
	if nxt != current_q_idx:
		current_q_idx = nxt
		_refresh_exam_paper_ui()
		_refresh_cheat_sheet_ui()
		_show_toast("📄 切換至第 %d / %d 題" % [current_q_idx + 1, questions.size()])

func _calculate_score() -> int:
	var s := 0
	for q in questions:
		if q["user_ans"] == q["correct"]:
			s += 10
	return s

func _answered_count() -> int:
	var c := 0
	for q in questions:
		if q["user_ans"] != -1:
			c += 1
	return c

func _submit_exam_early() -> void:
	var sc := _calculate_score()
	if sc >= 90:
		_trigger_end(GameState.VICTORY)
	else:
		_trigger_end(GameState.TIMEOUT_FAIL)

func _trigger_end(st: GameState) -> void:
	game_state = st
	gameover_panel.visible = true
	var sc := _calculate_score()
	if st == GameState.BUSTED:
		gameover_title_lbl.text = "【伸手看抽屜小抄被奶龍抓包！慘遭當掉！】"
		gameover_title_lbl.add_theme_color_override("font_color", Color(0.95, 0.25, 0.25))
		gameover_sub_lbl.text = "奶龍走到你 3D 書桌前捧著大肚子狂笑：『手伸進抽屜裡翻什麼？零分！』\n你已被記下學號移送獎懲會處理！"
	elif st == GameState.TIMEOUT_FAIL:
		gameover_title_lbl.text = "【成績未達 90 分！只能辦停修！】"
		gameover_title_lbl.add_theme_color_override("font_color", Color(0.95, 0.45, 0.20))
		gameover_sub_lbl.text = "最終得分：%d 分 (過關門檻：90 分 A+)\n奶龍摸摸肚子搖搖頭：未達 90 分只能去辦停修了！" % sc
	elif st == GameState.VICTORY:
		gameover_title_lbl.text = "【恭喜通關！成功奪得 A+！】"
		gameover_title_lbl.add_theme_color_override("font_color", Color(0.20, 0.90, 0.45))
		gameover_sub_lbl.text = "最終成績：%d 分！\n你在 3D 考場中精準控制抽屜小抄、心率與腦波專注度，完美瞞過奶龍監考官！" % sc

func _process(delta: float) -> void:
	_poll_external_udp()

	if toast_timer > 0.0:
		toast_timer -= delta
		if toast_timer <= 0.0:
			toast_panel.visible = false

	# 鄰座同學寫字手臂動態
	var t_ms := Time.get_ticks_msec() * 0.001
	for i in range(classmate_arms.size()):
		classmate_arms[i].position.x = 0.18 + sin(t_ms * 7.0 + float(i)) * 0.035

	if game_state != GameState.PLAYING:
		return

	# 1. 滑鼠控制 3D 第一人稱視角 (Yaw 左右看同學、Pitch 上下看奶龍/書桌考卷/抽屜)
	var mpos := get_viewport().get_mouse_position()
	if mpos.x < 890:
		var nx := clampf((mpos.x / 890.0) * 2.0 - 1.0, -1.0, 1.0)
		var ny := clampf((mpos.y / 720.0) * 2.0 - 1.0, -1.0, 1.0)
		target_yaw = -nx * 0.72
		target_pitch = -ny * 0.32 - 0.30
	else:
		target_yaw = 0.0
		target_pitch = -0.30

	cam_yaw = lerpf(cam_yaw, target_yaw, minf(1.0, delta * 10.0))
	cam_pitch = lerpf(cam_pitch, target_pitch, minf(1.0, delta * 10.0))
	camera.rotation = Vector3(cam_pitch, cam_yaw, 0.0)

	# 檢查 3D 桌面考卷懸停高亮
	var hov := _raycast_desk_paper_uv(mpos)
	if hov != hovered_exam_item:
		hovered_exam_item = hov
		_refresh_exam_paper_ui()

	# 2. 更新抽屜滑出與伸手翻小抄 3D 動畫
	var target_emg := 1.0 if emg_active else 0.0
	emg_level = lerpf(emg_level, target_emg, minf(1.0, delta * 12.0))
	drawer_pivot.position.z = -0.64 + emg_level * 0.34
	hands_pivot.position = Vector3(0.0, 0.42 + emg_level * 0.21, 0.22 - emg_level * 0.44)
	hands_pivot.visible = (emg_level > 0.03)
	cheat_mesh_inst.scale = Vector3(maxf(0.15, emg_level), maxf(0.25, emg_level), 1.0)

	# 3. 更新 ECG 與 EEG 生理訊號
	if bio_mode == BioMode.MANUAL:
		var stress := (22.0 if emg_active else 0.0) + (28.0 if buzzer_active else 0.0)
		if is_deep_breathing:
			base_bpm = lerpf(base_bpm, 65.0, minf(1.0, delta * 3.0))
			ecg_bpm = lerpf(ecg_bpm, 65.0, minf(1.0, delta * 4.5))
		else:
			var tgt := base_bpm + stress
			var rate := 2.5 if tgt > ecg_bpm else 1.8
			ecg_bpm = clampf(lerpf(ecg_bpm, tgt, minf(1.0, delta * rate)), 45.0, 170.0)
		eeg_focus = clampf(eeg_focus + (randf() - 0.5) * 0.6 * delta, 5.0, 100.0)

	# P-Q-R-S-T 波形生成並推入 HUD 示波器
	var cyc := 60.0 / maxf(40.0, ecg_bpm)
	beat_phase += delta / cyc
	while beat_phase >= 1.0:
		beat_phase -= 1.0
	var p := beat_phase
	var w_val := 0.0
	if p >= 0.12 and p <= 0.22:
		w_val += 0.18 * sin((p - 0.12) / 0.10 * PI)
	elif p >= 0.32 and p <= 0.35:
		w_val -= 0.15 * sin((p - 0.32) / 0.03 * PI)
	elif p >= 0.35 and p <= 0.40:
		w_val += 1.00 * sin((p - 0.35) / 0.05 * PI)
	elif p >= 0.40 and p <= 0.44:
		w_val -= 0.35 * sin((p - 0.40) / 0.04 * PI)
	elif p >= 0.55 and p <= 0.72:
		w_val += 0.28 * sin((p - 0.55) / 0.17 * PI)
	ecg_scope.push_sample(w_val + 0.03 * sin(t_ms * 3.0), ecg_bpm)

	# 4. 更新奶龍監考官 AI 與 3D 走道巡邏
	_update_teacher_ai(delta, t_ms)

	# 5. 更新考試時間倒數与 HUD 數值
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_submit_exam_early()

	_refresh_cheat_sheet_ui()
	_update_live_hud_labels()

func _poll_external_udp() -> void:
	while udp_server.get_available_packet_count() > 0:
		var pkt := udp_server.get_packet().get_string_from_utf8().strip_edges()
		if pkt == "":
			continue
		var parts := pkt.split(",")
		for part in parts:
			if ":" in part:
				var kv := part.split(":")
				var k := kv[0].strip_edges().to_upper()
				var v := float(kv[1].strip_edges())
				if k in ["ECG", "BPM"]:
					ecg_bpm = clampf(v, 40.0, 180.0)
					base_bpm = ecg_bpm
				elif k in ["EEG", "FOCUS"]:
					eeg_focus = clampf(v, 0.0, 100.0)
					eeg_target_focus = eeg_focus
				elif k == "EMG":
					emg_active = (v > 0.5)
		external_source_name = "UDP:5005"
		external_packet_count += 1
		last_external_time = Time.get_ticks_msec() * 0.001

func _update_teacher_ai(delta: float, t_ms: float) -> void:
	teacher_timer -= delta
	var hr_factor := maxf(0.0, (ecg_bpm - 75.0) / 50.0)

	match teacher_state:
		TeacherState.WRITING_BOARD:
			facing_player = false
			buzzer_active = false
			patrol_progress = 0.0
			teacher_chalk_arm.position.y = 0.95 + sin(t_ms * 10.0) * 0.08
			if teacher_timer <= 0.0:
				teacher_state = TeacherState.BUZZER_WARNING
				buzzer_active = true
				teacher_timer = randf_range(1.6, 2.5)

		TeacherState.BUZZER_WARNING:
			facing_player = false
			buzzer_active = true
			teacher_back_group.position.x = sin(t_ms * 35.0) * 0.05
			if teacher_timer <= 0.0:
				teacher_back_group.position.x = 0.0
				buzzer_active = false
				var fake_prob := maxf(0.15, 0.42 - hr_factor * 0.25)
				if randf() < fake_prob:
					teacher_state = TeacherState.FALSE_ALARM
					teacher_timer = 2.0
				else:
					teacher_state = TeacherState.TURNING_AROUND
					facing_player = true
					teacher_timer = 1.2

		TeacherState.FALSE_ALARM:
			facing_player = false
			if teacher_timer <= 0.0:
				teacher_state = TeacherState.WRITING_BOARD
				teacher_timer = maxf(2.5, randf_range(4.5, 7.5) - hr_factor * 2.0)

		TeacherState.TURNING_AROUND:
			facing_player = true
			if teacher_timer <= 0.0:
				teacher_state = TeacherState.PATROLLING
				teacher_timer = randf_range(3.5, 5.2)

		TeacherState.PATROLLING:
			facing_player = true
			patrol_progress = minf(1.0, patrol_progress + delta * 0.55)
			if teacher_timer <= 0.0:
				teacher_state = TeacherState.RETURNING
				teacher_timer = 2.0

		TeacherState.RETURNING:
			facing_player = false
			patrol_progress = maxf(0.0, patrol_progress - delta * 0.65)
			if teacher_timer <= 0.0:
				patrol_progress = 0.0
				teacher_state = TeacherState.WRITING_BOARD
				teacher_timer = maxf(2.5, randf_range(4.5, 7.5) - hr_factor * 2.0)

	teacher_back_group.visible = not facing_player
	teacher_front_sprite.visible = facing_player
	var tz := -6.2 + patrol_progress * 4.75
	var tx := sin(t_ms * 10.0) * 0.12 * patrol_progress if teacher_state == TeacherState.PATROLLING else 0.0
	var ty := 0.22 * (1.0 - minf(1.0, patrol_progress * 2.5))
	teacher_root.position = Vector3(tx, ty, tz)

	if buzzer_active:
		var blink := (int(t_ms * 7.0) % 2) == 0
		buzzer_mesh_mat.albedo_color = Color(1.0, 0.2, 0.2) if blink else Color(1.0, 0.82, 0.0)
	else:
		buzzer_mesh_mat.albedo_color = Color(0.22, 0.26, 0.28)

	# 抓包判定：奶龍正面看向玩家且抽屜小抄未收起
	if facing_player and emg_level > 0.22:
		_trigger_end(GameState.BUSTED)

func _refresh_exam_paper_ui() -> void:
	var q := questions[current_q_idx]
	exam_header_label.text = "【期末考卷】第 %d / %d 題" % [current_q_idx + 1, questions.size()]
	exam_q_label.text = q["prompt"]

	for i in range(4):
		var is_sel: bool = (q["user_ans"] == i)
		var is_hov: bool = (hovered_exam_item == ("OPT_%d" % i))
		var st := StyleBoxFlat.new()
		if is_sel:
			st.bg_color = Color(0.84, 0.92, 1.0)
			st.border_color = Color(0.16, 0.50, 0.73)
			st.set_border_width_all(3)
		elif is_hov:
			st.bg_color = Color(0.93, 0.96, 1.0)
			st.border_color = Color(0.45, 0.65, 0.85)
			st.set_border_width_all(2)
		else:
			st.bg_color = Color(1.0, 1.0, 1.0)
			st.border_color = Color(0.78, 0.77, 0.74)
			st.set_border_width_all(2)
		st.set_corner_radius_all(6)
		exam_opt_panels[i].add_theme_stylebox_override("panel", st)
		exam_opt_labels[i].text = q["options"][i]

func _refresh_cheat_sheet_ui() -> void:
	var q := questions[current_q_idx]
	var alpha_norm := 0.03
	if eeg_focus > 25.0:
		var n := clampf((eeg_focus - 25.0) / 60.0, 0.0, 1.0)
		alpha_norm = 0.03 + pow(n, 1.3) * 0.97

	var clarity := "近乎隱形 (完全看不清)"
	if eeg_focus >= 80.0:
		clarity = "極度清晰 (100% 不透明)"
	elif eeg_focus >= 55.0:
		clarity = "清晰可讀 (良好)"
	elif eeg_focus >= 35.0:
		clarity = "渙散半透明 (勉強)"

	cheat_title_lbl.text = "【抽屜內展開小抄】EEG 專注度: %.0f%% (%s)" % [eeg_focus, clarity]
	cheat_title_lbl.modulate.a = alpha_norm
	cheat_body_lbl.text = q["hint"]
	cheat_body_lbl.modulate.a = alpha_norm
	cheat_warn_lbl.visible = (eeg_focus <= 35.0)
	eeg_clarity_lbl.text = "小抄清晰度：%s" % clarity

func _update_mode_ui() -> void:
	var is_ext := (bio_mode == BioMode.EXTERNAL)
	var badge_st := StyleBoxFlat.new()
	badge_st.bg_color = Color(0.60, 0.35, 0.71) if is_ext else Color(0.15, 0.68, 0.38)
	badge_st.set_corner_radius_all(5)
	top_mode_badge.add_theme_stylebox_override("panel", badge_st)
	top_mode_lbl.text = "【模式二：外部訊號輸入】" if is_ext else "【模式一：手動調控測試】"

	btn_switch_mode.text = "★ 目前：外部訊號模式 (點此或按 M 切換)" if is_ext else "★ 目前：手動調控模式 (點此或按 M 切換)"
	btn_emg_hud.text = "【已伸手打開抽屜小抄】空白鍵/點此收回" if emg_active else "【小抄在抽屜裡】按空白鍵/點此伸手打開"

	btn_bpm_down.text = "[鎖]BPM▼" if is_ext else "BPM▼ (↓)"
	btn_bpm_up.text = "[鎖]BPM▲" if is_ext else "BPM▲ (↑)"
	btn_breathe.text = "[鎖定]外部控制" if is_ext else "★ 深呼吸(按R)"
	btn_focus_down.text = "[鎖]分心 (外部)" if is_ext else "腦波分心 (S鍵)"
	btn_focus_up.text = "[鎖]專注 (外部)" if is_ext else "腦波專注 (W鍵)"

func _update_live_hud_labels() -> void:
	var mins := int(time_left) / 60
	var secs := int(time_left) % 60
	top_time_lbl.text = "剩餘時間：%02d:%02d" % [mins, secs]
	top_score_lbl.text = "已答: %d/10 | 預估分: %d 分 (過關: 90分)" % [_answered_count(), _calculate_score()]

	emg_bar.value = emg_level * 100.0
	emg_bar_lbl.text = "伸手抽屜開度 (EMG電位): %.0f%%" % (emg_level * 100.0)
	ecg_title_lbl.text = "2. ECG 心電 [%.0f BPM] %s" % [ecg_bpm, "[外部輸入]" if bio_mode == BioMode.EXTERNAL else "(↑/↓ 微調)"]
	eeg_title_lbl.text = "3. EEG 專注度 [%.0f%%] %s" % [eeg_focus, "[外部輸入]" if bio_mode == BioMode.EXTERNAL else "(W/S 微調)"]
	eeg_bar.value = eeg_focus

	# 奶龍狀態列
	var t_txt := "★ 奶龍正挺著大肚子在黑板寫板書（安全期！可伸手開抽屜看小抄！）"
	var t_col := Color(0.18, 0.80, 0.44)
	match teacher_state:
		TeacherState.BUZZER_WARNING:
			t_txt = "【逼逼！警戒！】蜂鳴器響起！奶龍的大肚子開始抖動了！（可能在憋笑假動作）"
			t_col = Color(0.95, 0.77, 0.06)
		TeacherState.FALSE_ALARM:
			t_txt = "★ 奶龍只是轉身摸摸肚子抓癢，虛驚一場！"
			t_col = Color(0.65, 0.85, 0.45)
		TeacherState.TURNING_AROUND:
			t_txt = "【哈哈哈哈！】奶龍捧著大肚子轉身狂笑！眼神掃視全場！"
			t_col = Color(0.92, 0.30, 0.24)
		TeacherState.PATROLLING:
			t_txt = "【極度危險】奶龍挺著大肚子走下講台巡查走道中！！千萬別開抽屜看小抄！"
			t_col = Color(1.0, 0.22, 0.22)
		TeacherState.RETURNING:
			t_txt = "奶龍巡查完畢，搖頭晃腦走回講台..."
			t_col = Color(0.60, 0.72, 0.88)

	teacher_status_lbl.text = t_txt
	teacher_status_lbl.add_theme_color_override("font_color", t_col)
	var tsp_st := StyleBoxFlat.new()
	tsp_st.bg_color = Color(0.10, 0.13, 0.17, 0.94)
	tsp_st.border_color = t_col
	tsp_st.set_border_width_all(2)
	tsp_st.set_corner_radius_all(6)
	teacher_status_panel.add_theme_stylebox_override("panel", tsp_st)

	var yaw_d := int(rad_to_deg(-cam_yaw))
	var pitch_d := int(rad_to_deg(cam_pitch))
	var dir_s := "★ 視角：正前方書桌與講台 (移動滑鼠自由轉頭)"
	if yaw_d < -12:
		dir_s = "★ 視角：往左轉頭看鄰座同學與窗戶"
	elif yaw_d > 12:
		dir_s = "★ 視角：往右轉頭看鄰座同學與教室門"
	elif pitch_d > -14:
		dir_s = "★ 視角：抬頭注視黑板與奶龍監考官"
	elif pitch_d < -24:
		dir_s = "★ 視角：低頭注視書桌考卷與抽屜內部"
	cam_dir_lbl.text = "%s (%d°, %d°)" % [dir_s, yaw_d, pitch_d]

	if bio_mode == BioMode.MANUAL:
		guide_lbl.text = "【3D 教室視角 & 手動模式指南】\n• 滑鼠移動：自由轉動 3D 第一人稱視角\n  - 往上移：抬頭看黑板與奶龍監考官\n  - 往左右：轉頭看旁邊其他學生作答\n  - 往下移：低頭看書桌考卷與抽屜小抄\n• [空白鍵/右鍵/EMG]：伸手拉開抽屜看小抄\n• [↑ / ↓] 調控 ECG 心率 | [R] 深呼吸\n• [W / S] 調控 EEG 專注度 | [M] 切換模式"
	else:
		var now_s := Time.get_ticks_msec() * 0.001
		var live := (now_s - last_external_time) < 3.0
		var st_line := "🟢 已連線接收 (%s | 封包:%d)" % [external_source_name, external_packet_count] if live else "🟡 等待外部輸入 ECG, EEG (UDP:5005)..."
		guide_lbl.text = "【模式二：外部訊號輸入 (UDP:5005)】\n%s\n\n• 手動 ECG/EEG 已鎖定！必須從外部輸入\n• 抽屜小抄 (EMG) 維持由 [空白鍵/右鍵] 控制\n• 外部傳入格式：ECG:85,EEG:78\n• 可執行資料夾內 external_signal_sender.py\n  或連接 Arduino 傳入訊號！" % st_line
