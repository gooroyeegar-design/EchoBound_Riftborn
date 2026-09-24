extends Control

# ECHObound: RIFTBORN
# Commercial-ready vertical-slice foundation.
# Godot 4.x / mobile-first / no external runtime dependencies.

const SAVE_PATH := "user://echobound_save.json"
const VERSION := 2
const OFFLINE_CAP := 28800

var state := {
	"version": VERSION,
	"player": {"level":1,"xp":0,"gold":150,"crystals":10,"hp":120,"max_hp":120,"damage":18,"crit":8,"energy":20,"max_energy":20},
	"world": {"zone":0,"chapter":1,"wave":1,"defeated":0,"bosses":0,"keys":0},
	"heroes": {
		"Nova":{"unlocked":true,"level":1,"power":1.0},
		"Rune":{"unlocked":false,"level":1,"power":1.0},
		"Mira":{"unlocked":false,"level":1,"power":1.0},
		"Kael":{"unlocked":false,"level":1,"power":1.0}
	},
	"outfits":["Rookie Jacket"],
	"equipped_outfit":"Rookie Jacket",
	"equipped_hero":"Nova",
	"upgrades":{"power":0,"crit":0,"armor":0,"auto_hunt":0,"energy":0},
	"quests":{"defeated":0,"gold_earned":0,"bosses":0,"level":1,"claimed":[]},
	"inventory":{"potions":2,"keys":0},
	"achievements":[],
	"story_flags":[],
	"last_seen":0
}

var enemy := {}
var rng := RandomNumberGenerator.new()
var log_lines:Array[String] = []
var toast_timer := 0.0
var idle_timer := 0.0
var autosave_timer := 0.0
var combo := 0
var combo_timer := 0.0
var selected_tab := "World"
var ui := {}

var zones := [
	{"name":"Whisperwood","emoji":"🌲","min":1,"chapter":1,"desc":"The fallen star sleeps beneath ancient roots."},
	{"name":"Ember Wastes","emoji":"🔥","min":6,"chapter":2,"desc":"A sunless desert burns from below."},
	{"name":"Celestial Ruins","emoji":"☄","min":13,"chapter":3,"desc":"Floating ruins guard the second Echo."},
	{"name":"The Rift","emoji":"◉","min":20,"chapter":4,"desc":"Reality ends here. The voice begins."},
	{"name":"Eclipse Citadel","emoji":"♜","min":30,"chapter":5,"desc":"The final fortress of the forgotten king."}
]

var enemy_defs := [
	{"name":"Voidling","icon":"✦","hp":90,"gold":28,"xp":35,"boss":false},
	{"name":"Moss Warden","icon":"♣","hp":145,"gold":42,"xp":52,"boss":false},
	{"name":"Rift Hound","icon":"◇","hp":215,"gold":60,"xp":72,"boss":false},
	{"name":"THORNMAW","icon":"◆","hp":680,"gold":220,"xp":260,"boss":true},
	{"name":"Ash Golem","icon":"⬢","hp":900,"gold":285,"xp":330,"boss":false},
	{"name":"Solar Serpent","icon":"☼","hp":1400,"gold":420,"xp":480,"boss":false},
	{"name":"THE ASTRAL KING","icon":"★","hp":3400,"gold":1100,"xp":1200,"boss":true},
	{"name":"Void Reaper","icon":"☠","hp":5200,"gold":1650,"xp":1700,"boss":false},
	{"name":"THE ECHO","icon":"◎","hp":12000,"gold":5000,"xp":6000,"boss":true}
]

var outfits := [
	["Rookie Jacket","🧥","Starting outfit"],
	["Starlight Cloak","✦","Reach level 3"],
	["Forest Guardian","🌿","Defeat 25 enemies"],
	["Ember Knight","🔥","Reach level 8"],
	["Rift Hunter","⚔","Defeat 3 bosses"],
	["Astral Regent","👑","Reach level 20"],
	["Voidwalker","◉","Complete the story"],
	["Eclipse Sovereign","♜","Defeat The Echo"]
]

var hero_defs := [
	["Nova","🧑‍🚀","Star Runner","Balanced fighter","1"],
	["Rune","🧙","Rift Mage","Huge skill damage","8"],
	["Mira","🏹","Dawn Archer","Critical specialist","13"],
	["Kael","🛡","Eclipse Knight","Tank + counter attacks","22"]
]

func _ready():
	rng.randomize()
	load_game()
	apply_offline_progress()
	build_ui()
	start_enemy()
	write_log("🌠 The fallen star has chosen you.")
	write_log("📖 Chapter 1: The Sleeping Star begins.")
	update_ui()

func _process(delta):
	toast_timer = maxf(0.0,toast_timer-delta)
	idle_timer += delta
	autosave_timer += delta
	combo_timer -= delta
	if combo_timer <= 0: combo = 0
	if idle_timer >= 5.0:
		idle_timer = 0
		if int(state.upgrades.auto_hunt) > 0:
			for i in range(int(state.upgrades.auto_hunt)):
				perform_attack(true)
		else:
			recover_energy()
	if autosave_timer >= 10.0:
		autosave_timer = 0
		save_game()
	if ui.has("toast") and toast_timer <= 0:
		ui.toast.visible = false

func build_ui():
	for c in get_children(): c.queue_free()
	var bg=ColorRect.new()
	bg.color=Color("#080812")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll=ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	var root=VBoxContainer.new()
	root.custom_minimum_size=Vector2(0,1900)
	root.add_theme_constant_override("separation",10)
	scroll.add_child(root)

	# Hero header
	var header=panel()
	header.custom_minimum_size.y=145
	root.add_child(header)
	var hv=VBoxContainer.new(); header.add_child(hv)
	ui.title=label("ECHOBOUND",15,Color("#9d8cff")); hv.add_child(ui.title)
	ui.hero_title=label("RIFTBORN",36,Color.WHITE); hv.add_child(ui.hero_title)
	ui.hero_sub=label("An idle action RPG about a world that forgot its own hero.",12,Color("#9b9bb0")); hv.add_child(ui.hero_sub)
	var row=HBoxContainer.new(); hv.add_child(row)
	ui.level=label("",15,Color.WHITE); row.add_child(ui.level)
	var sp=Control.new(); sp.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(sp)
	ui.currency=label("",14,Color("#ffd166")); row.add_child(ui.currency)

	ui.xp=ProgressBar.new(); ui.xp.custom_minimum_size.y=12; ui.xp.show_percentage=false; hv.add_child(ui.xp)
	ui.hp=ProgressBar.new(); ui.hp.custom_minimum_size.y=12; ui.hp.show_percentage=false; hv.add_child(ui.hp)

	# Navigation
	var nav=HBoxContainer.new(); nav.add_theme_constant_override("separation",6); root.add_child(nav)
	for tab in ["World","Heroes","Quests","Outfits","Upgrades"]:
		var b=button(tab,13); b.size_flags_horizontal=Control.SIZE_EXPAND_FILL; nav.add_child(b)
		var t=tab; b.pressed.connect(func(): switch_tab(t))

	ui.content=VBoxContainer.new()
	ui.content.add_theme_constant_override("separation",10)
	root.add_child(ui.content)

	ui.toast=label("",14,Color.WHITE); ui.toast.visible=false; ui.toast.position=Vector2(20,20); add_child(ui.toast)

func switch_tab(tab):
	selected_tab=tab
	render_content()

func render_content():
	for c in ui.content.get_children(): c.queue_free()
	match selected_tab:
		"World": render_world()
		"Heroes": render_heroes()
		"Quests": render_quests()
		"Outfits": render_outfits()
		"Upgrades": render_upgrades()

func render_world():
	var story=panel(); ui.content.add_child(story)
	var sv=VBoxContainer.new(); story.add_child(sv)
	var z=zones[int(state.world.zone)]
	var ch=label("CHAPTER %d  •  %s %s" % [int(state.world.chapter),z.emoji,z.name],20,Color.WHITE); sv.add_child(ch)
	var st=label(chapter_text(),13,Color("#a9a9bf")); st.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; sv.add_child(st)

	var combat=panel(); combat.custom_minimum_size.y=350; ui.content.add_child(combat)
	var cv=VBoxContainer.new(); combat.add_child(cv)
	var top=HBoxContainer.new(); cv.add_child(top)
	var et=label(str(enemy.name),22,Color.WHITE); top.add_child(et)
	var spacer=Control.new(); spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL; top.add_child(spacer)
	top.add_child(label("WAVE %d" % int(state.world.wave),12,Color("#9999ad")))
	var icon=label(str(enemy.icon),78,Color("#c6b8ff")); icon.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; cv.add_child(icon)
	var ehp=ProgressBar.new(); ehp.custom_minimum_size.y=20; ehp.show_percentage=false; ehp.max_value=enemy.max_hp; ehp.value=enemy.hp; cv.add_child(ehp)
	var etxt=label("%d / %d HP   •   🪙 %d" % [max(0,int(enemy.hp)),int(enemy.max_hp),int(enemy.gold)],12,Color("#a2a2b7")); etxt.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; cv.add_child(etxt)
	var actions=HBoxContainer.new(); actions.add_theme_constant_override("separation",8); cv.add_child(actions)
	var attack=button("⚔ ATTACK",18); attack.size_flags_horizontal=Control.SIZE_EXPAND_FILL; actions.add_child(attack); attack.pressed.connect(func():perform_attack(false))
	var skill=button("✦ RIFT BURST",18); skill.size_flags_horizontal=Control.SIZE_EXPAND_FILL; skill.disabled=state.player.energy<5; actions.add_child(skill); skill.pressed.connect(use_skill)
	var meta=label("⚡ %d/%d   •   Combo x%d   •   Crit %d%%" % [int(state.player.energy),int(state.player.max_energy),combo,int(state.player.crit)],13,Color("#c4c4d4")); cv.add_child(meta)

	var zones_panel=panel(); ui.content.add_child(zones_panel)
	var zv=VBoxContainer.new(); zones_panel.add_child(zv)
	zv.add_child(label("WORLD MAP",20,Color.WHITE))
	for i in range(zones.size()):
		var zz=zones[i]
		var unlocked=state.player.level>=int(zz.min)
		var b=button("%s  %s\n%s" % [zz.emoji,zz.name,zz.desc],13); b.custom_minimum_size.y=66; b.alignment=HORIZONTAL_ALIGNMENT_LEFT; b.disabled=not unlocked; zv.add_child(b)
		var idx=i; b.pressed.connect(func():travel_to(idx))
		if not unlocked: b.text+="\n🔒 Level %d" % int(zz.min)

func render_heroes():
	var p=panel(); ui.content.add_child(p); var v=VBoxContainer.new(); p.add_child(v)
	v.add_child(label("HERO ROSTER",23,Color.WHITE))
	v.add_child(label("Each hero changes the way your build plays.",12,Color("#9999ad")))
	for h in hero_defs:
		var name=h[0]; var data=state.heroes[name]
		var req=int(h[4]); var unlocked=bool(data.unlocked) or state.player.level>=req
		var text="%s  %s  %s\n%s • %s" % [h[1],name,h[2],h[3],"UNLOCKED" if unlocked else "🔒 Level %d"%req]
		var b=button(text,14); b.custom_minimum_size.y=75; b.alignment=HORIZONTAL_ALIGNMENT_LEFT; b.disabled=not unlocked; v.add_child(b)
		b.pressed.connect(func():select_hero(name))

	var info=panel(); ui.content.add_child(info); var iv=VBoxContainer.new(); info.add_child(iv)
	iv.add_child(label("CURRENT HERO",18,Color.WHITE))
	iv.add_child(label("🧑‍🚀 %s  •  Level %d" % [state.equipped_hero,int(state.heroes[state.equipped_hero].level)],14,Color("#d5d5e5")))
	iv.add_child(label(hero_ability_text(state.equipped_hero),13,Color("#9c9caf")))

func render_quests():
	var p=panel(); ui.content.add_child(p); var v=VBoxContainer.new(); p.add_child(v)
	v.add_child(label("QUEST BOARD",23,Color.WHITE))
	add_quest(v,"First Hunt","Defeat 5 enemies",min(int(state.world.defeated),5),5,120,"q1")
	add_quest(v,"Fortune Finder","Earn 500 gold",min(int(state.quests.gold_earned),500),500,3,"q2")
	add_quest(v,"Boss Breaker","Defeat 3 bosses",min(int(state.world.bosses),3),3,8,"q3")
	add_quest(v,"Veteran","Reach level 10",min(int(state.player.level),10),10,5,"q4")
	add_quest(v,"Riftwalker","Reach level 20",min(int(state.player.level),20),20,12,"q5")
	add_quest(v,"End of Echo","Defeat The Echo",1 if state.world.keys>=1 else 0,1,25,"q6")

	var p2=panel(); ui.content.add_child(p2); var vv=VBoxContainer.new(); p2.add_child(vv)
	vv.add_child(label("DAILY CHALLENGES",20,Color.WHITE))
	vv.add_child(label("Daily challenge system is designed for rotating goals in production.",12,Color("#9999ad")))
	vv.add_child(label("• Defeat 20 enemies  •  Use 5 Rift Bursts  •  Earn 1,000 gold",13,Color("#d0d0df")))

func add_quest(parent,title,desc,progress,goal,reward,key):
	var claimed=state.quests.claimed.has(key)
	var b=button("%s\n%s  •  %d/%d  •  💎 %d%s" % [title,desc,progress,goal,reward,"  ✓ CLAIMED" if claimed else ""],13)
	b.custom_minimum_size.y=70; b.alignment=HORIZONTAL_ALIGNMENT_LEFT; b.disabled=claimed or progress<goal; parent.add_child(b)
	b.pressed.connect(func():claim_quest(key,reward))

func render_outfits():
	var p=panel(); ui.content.add_child(p); var v=VBoxContainer.new(); p.add_child(v)
	v.add_child(label("OUTFIT VAULT",23,Color.WHITE))
	v.add_child(label("Cosmetic rewards are earned through gameplay.",12,Color("#9999ad")))
	for o in outfits:
		var owned=state.outfits.has(o[0]); var equipped=state.equipped_outfit==o[0]
		var b=button("%s  %s\n%s%s" % [o[1],o[0],o[2],"  • EQUIPPED" if equipped else ""],14)
		b.custom_minimum_size.y=64; b.alignment=HORIZONTAL_ALIGNMENT_LEFT; b.disabled=not owned; v.add_child(b)
		var n=o[0]; b.pressed.connect(func():equip_outfit(n))

func render_upgrades():
	var p=panel(); ui.content.add_child(p); var v=VBoxContainer.new(); p.add_child(v)
	v.add_child(label("UPGRADE LAB",23,Color.WHITE))
	v.add_child(label("Build your hero for active play or idle progression.",12,Color("#9999ad")))
	add_upgrade(v,"power","⚔ Power","Damage +7")
	add_upgrade(v,"crit","🎯 Critical","Crit +4%")
	add_upgrade(v,"armor","🛡 Armor","Max HP +30")
	add_upgrade(v,"energy","⚡ Energy","Max energy +2")
	add_upgrade(v,"auto_hunt","🤖 Auto Hunt","One extra idle action per level")
	var reset=button("SAVE GAME",14); v.add_child(reset); reset.pressed.connect(func():save_game();show_toast("Game saved"))

func add_upgrade(parent,key,title,desc):
	var lvl=int(state.upgrades[key])
	var cost=upgrade_cost(key,lvl)
	var b=button("%s  •  Lv.%d\n%s  •  🪙 %d" % [title,lvl,desc,cost],14); b.custom_minimum_size.y=68; b.alignment=HORIZONTAL_ALIGNMENT_LEFT; parent.add_child(b)
	b.pressed.connect(func():buy_upgrade(key))

func panel():
	var p=PanelContainer.new()
	p.add_theme_stylebox_override("panel",make_box("#12121f","#302d48",16))
	return p

func button(t,s):
	var b=Button.new(); b.text=t; b.add_theme_font_size_override("font_size",s); b.focus_mode=Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal",make_box("#19192a","#353553",12))
	b.add_theme_stylebox_override("hover",make_box("#24243d","#635995",12))
	b.add_theme_stylebox_override("pressed",make_box("#302851","#8f79ee",12))
	return b

func label(t,s,c):
	var l=Label.new(); l.text=t; l.add_theme_font_size_override("font_size",s); l.add_theme_color_override("font_color",c); return l

func make_box(fill,border,radius):
	var s=StyleBoxFlat.new(); s.bg_color=Color(fill); s.border_color=Color(border); s.set_border_width_all(1); s.set_corner_radius_all(radius)
	s.content_margin_left=13;s.content_margin_right=13;s.content_margin_top=9;s.content_margin_bottom=9;return s

func start_enemy():
	var zone=int(state.world.zone)
	var idx=min(enemy_defs.size()-1, int(state.world.wave-1)%enemy_defs.size())
	if zone>=4 and state.world.wave%5==0: idx=8
	elif zone>=3 and state.world.wave%5==0: idx=6
	var base=enemy_defs[idx]
	var scale=1.0+float(state.player.level-1)*0.10+zone*0.22+max(0,int(state.world.wave/10))*0.15
	enemy=base.duplicate()
	enemy.max_hp=int(base.hp*scale); enemy.hp=enemy.max_hp
	enemy.gold=int(base.gold*(1.0+state.player.level*0.045))
	enemy.xp=int(base.xp*(1.0+state.player.level*0.04))

func perform_attack(idle=false):
	if enemy.hp<=0:return
	var hero=state.equipped_hero
	var mult=1.0
	if hero=="Rune": mult=1.15
	if hero=="Mira" and rng.randf()<0.25: mult=2.2
	if hero=="Kael" and rng.randf()<0.15: mult=1.6
	var crit=rng.randf()*100<float(state.player.crit)
	var dmg=int(float(state.player.damage)*mult*(2.0 if crit else 1.0))
	enemy.hp-=dmg
	if not idle:
		state.player.energy=max(0,state.player.energy-1)
		combo+=1;combo_timer=3.0
	if crit and not idle:show_toast("💥 CRITICAL %d!"%dmg)
	if enemy.hp<=0:defeat_enemy()
	else:
		var retaliation=rng.randi_range(2,7)+int(state.world.zone)*2
		if hero=="Kael": retaliation=int(retaliation*0.65)
		state.player.hp=max(1,state.player.hp-retaliation)
	update_ui()

func use_skill():
	if state.player.energy<5:return
	state.player.energy-=5
	var mult=4.0
	if state.equipped_hero=="Rune":mult=6.0
	if state.equipped_hero=="Mira":mult=4.8
	if state.equipped_hero=="Kael":mult=3.5
	var dmg=int(state.player.damage*mult)
	enemy.hp-=dmg
	write_log("✦ Rift Burst deals %d damage."%dmg)
	if enemy.hp<=0:defeat_enemy()
	update_ui()

func defeat_enemy():
	var reward=int(enemy.gold);var xp=int(enemy.xp)
	state.player.gold+=reward;state.quests.gold_earned+=reward
	state.player.xp+=xp;state.world.defeated+=1;state.quests.defeated=state.world.defeated
	state.player.energy=min(state.player.max_energy,state.player.energy+3)
	if bool(enemy.boss):
		state.world.bosses+=1;state.quests.bosses=state.world.bosses
		write_log("👑 BOSS DEFEATED: %s • +%d gold"%[enemy.name,reward])
		if enemy.name=="THE ECHO":
			state.world.keys=1
			if not state.outfits.has("Voidwalker"):state.outfits.append("Voidwalker")
			write_log("🌌 THE STORY IS COMPLETE. But the world is not finished with you.")
	else:write_log("✓ %s defeated • +%d gold"%[enemy.name,reward])
	state.world.wave+=1
	check_level();check_unlocks();check_auto_quests()
	start_enemy();update_ui()

func check_level():
	while state.player.xp>=xp_required():
		state.player.xp-=xp_required();state.player.level+=1
		state.player.max_hp+=18;state.player.hp=state.player.max_hp;state.player.damage+=4
		state.player.max_energy+=1;state.player.energy=state.player.max_energy
		state.quests.level=state.player.level
		write_log("✨ LEVEL UP! You are now level %d."%state.player.level);show_toast("LEVEL %d!"%state.player.level)

func xp_required():return 90+int(state.player.level)*55

func upgrade_cost(key,lvl):
	match key:
		"power":return 80+lvl*70
		"crit":return 120+lvl*110
		"armor":return 100+lvl*85
		"energy":return 150+lvl*120
		"auto_hunt":return 250+lvl*250
	return 999999

func buy_upgrade(key):
	var lvl=int(state.upgrades[key]);var cost=upgrade_cost(key,lvl)
	if state.player.gold<cost:show_toast("Not enough gold");return
	state.player.gold-=cost;state.upgrades[key]=lvl+1
	match key:
		"power":state.player.damage+=7
		"crit":state.player.crit=min(60,state.player.crit+4)
		"armor":state.player.max_hp+=30;state.player.hp=state.player.max_hp
		"energy":state.player.max_energy+=2;state.player.energy=state.player.max_energy
		"auto_hunt":write_log("🤖 Auto Hunt level %d online."%(lvl+1))
	write_log("⬆ Upgrade purchased: %s"%key.replace("_"," ").capitalize());update_ui()

func travel_to(i):
	if state.player.level<int(zones[i].min):show_toast("Reach level %d"%int(zones[i].min));return
	state.world.zone=i;state.world.chapter=int(zones[i].chapter);state.world.wave=1
	write_log("🗺 Entered %s."%zones[i].name)
	if i==1:write_log("🔥 The fire beneath the sand is alive.")
	if i==2:write_log("☄ The ruins recognize your blood.")
	if i==3:write_log("◉ The Rift is speaking directly to you.")
	if i==4:write_log("♜ The Eclipse Citadel has opened.")
	start_enemy();selected_tab="World";render_content()

func select_hero(name):
	var req=int(state.heroes[name].get("requirement",0))
	for h in hero_defs:
		if h[0]==name:req=int(h[4])
	if not bool(state.heroes[name].unlocked) and state.player.level<req:show_toast("Unlocks at level %d"%req);return
	state.heroes[name].unlocked=true;state.equipped_hero=name
	write_log("🧑‍🤝‍🧑 %s is now your active hero."%name);show_toast(name+" selected");update_ui()

func equip_outfit(name):
	if not state.outfits.has(name):return
	state.equipped_outfit=name;write_log("👕 Equipped %s."%name);show_toast(name+" equipped");update_ui()

func claim_quest(key,reward):
	if state.quests.claimed.has(key):return
	state.quests.claimed.append(key);state.player.crystals+=reward;write_log("📜 Quest complete: %s • +%d crystals"%[key,reward]);show_toast("Quest reward!")

func check_auto_quests():
	check_unlocks()
	if state.world.defeated>=5 and not state.quests.claimed.has("q1_ready"):state.quests.claimed.append("q1_ready")
	if state.world.bosses>=3 and not state.quests.claimed.has("q3_ready"):state.quests.claimed.append("q3_ready")

func check_unlocks():
	if state.player.level>=3 and not state.outfits.has("Starlight Cloak"):state.outfits.append("Starlight Cloak");write_log("🎁 Outfit unlocked: Starlight Cloak")
	if state.world.defeated>=25 and not state.outfits.has("Forest Guardian"):state.outfits.append("Forest Guardian");write_log("🎁 Outfit unlocked: Forest Guardian")
	if state.player.level>=8 and not state.outfits.has("Ember Knight"):state.outfits.append("Ember Knight");write_log("🎁 Outfit unlocked: Ember Knight")
	if state.world.bosses>=3 and not state.outfits.has("Rift Hunter"):state.outfits.append("Rift Hunter");write_log("🎁 Outfit unlocked: Rift Hunter")
	if state.player.level>=20 and not state.outfits.has("Astral Regent"):state.outfits.append("Astral Regent");write_log("🎁 Outfit unlocked: Astral Regent")
	if state.world.keys>=1 and not state.outfits.has("Voidwalker"):state.outfits.append("Voidwalker")
	if state.world.keys>=1 and not state.outfits.has("Eclipse Sovereign"):state.outfits.append("Eclipse Sovereign")
	for h in hero_defs:
		if state.player.level>=int(h[4]):state.heroes[h[0]].unlocked=true

func hero_ability_text(name):
	match name:
		"Nova":return "Star Runner: balanced damage and reliable progression."
		"Rune":return "Rift Mage: Rift Burst deals 50% more damage."
		"Mira":return "Dawn Archer: 25% chance for a massive critical strike."
		"Kael":return "Eclipse Knight: reduces incoming damage and counters."
	return ""

func chapter_text():
	match int(state.world.chapter):
		1:return "A star fell into Whisperwood. You woke beside it with a mark on your hand. The village elder says the mark belonged to a hero who vanished 300 years ago."
		2:return "The Ember Wastes burn beneath an empty sky. Thornmaw guards a buried road leading to the second Echo Key."
		3:return "The Celestial Ruins float above the clouds. Their machines were built to contain something called the Echo."
		4:return "The Rift has no ground and no sky. The voice guiding you was never outside you."
		5:return "The Eclipse Citadel is the final fortress. Its king has been waiting for the hero he erased from history."
	return ""

func recover_energy():state.player.energy=min(state.player.max_energy,state.player.energy+1);update_ui()

func update_ui():
	if ui.is_empty():return
	var p=state.player
	ui.level.text="LEVEL %d   •   %d / %d XP"%[int(p.level),int(p.xp),xp_required()]
	ui.xp.max_value=xp_required();ui.xp.value=p.xp
	ui.hp.max_value=p.max_hp;ui.hp.value=p.hp
	ui.currency.text="🪙 %d   💎 %d   ⚡ %d/%d"%[int(p.gold),int(p.crystals),int(p.energy),int(p.max_energy)]
	render_content()
	if ui.has("toast") and toast_timer>0:ui.toast.visible=true

func show_toast(t):
	ui.toast.text=t;ui.toast.visible=true;toast_timer=2.0

func write_log(t):
	log_lines.push_front(t)
	if log_lines.size()>24:log_lines.pop_back()

func save_game():
	state.last_seen=int(Time.get_unix_time_from_system())
	var f=FileAccess.open(SAVE_PATH,FileAccess.WRITE)
	if f:f.store_string(JSON.stringify(state));f.close()

func load_game():
	if not FileAccess.file_exists(SAVE_PATH):return
	var f=FileAccess.open(SAVE_PATH,FileAccess.READ)
	if not f:return
	var parsed=JSON.parse_string(f.get_as_text());f.close()
	if parsed is Dictionary and int(parsed.get("version",0))==VERSION:merge_dict(state,parsed)

func merge_dict(target,source):
	for k in source:
		if target.has(k) and target[k] is Dictionary and source[k] is Dictionary:merge_dict(target[k],source[k])
		else:target[k]=source[k]

func apply_offline_progress():
	var last=int(state.last_seen)
	if last<=0:return
	var seconds=clamp(int(Time.get_unix_time_from_system())-last,0,OFFLINE_CAP)
	var auto=int(state.upgrades.auto_hunt)
	if auto>0 and seconds>=30:
		var ticks=min(360,int(seconds/5))
		var earned=ticks*auto*max(1,int(state.player.damage/10))
		state.player.gold+=earned
		write_log("🌙 While you were away: +%d gold."%earned)
