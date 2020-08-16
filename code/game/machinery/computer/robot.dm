/obj/machinery/computer/robotics
	name = "robotics control console"
	desc = "Used to remotely lockdown or detonate linked Cyborgs."
	icon = 'icons/obj/computer.dmi'
	icon_keyboard = "tech_key"
	icon_screen = "robot"
	req_access = list(ACCESS_ROBOTICS)
	circuit = /obj/item/circuitboard/robotics
	var/temp = null

	light_color = LIGHT_COLOR_PURPLE

	var/safety = 1

/obj/machinery/computer/robotics/attack_ai(var/mob/user as mob)
	return attack_hand(user)

/obj/machinery/computer/robotics/attack_hand(var/mob/user as mob)
	if(..())
		return
	if(stat & (NOPOWER|BROKEN))
		return
	tgui_interact(user)

/obj/machinery/computer/robotics/proc/is_authenticated(mob/user)
	if(user.can_admin_interact())
		return TRUE
	else if(allowed(user))
		return TRUE
	return FALSE

/// Does this robot show up on the console?
/obj/machinery/computer/robotics/proc/console_shows(mob/living/silicon/robot/R)
	if(!istype(R))
		return FALSE
	if(istype(R, /mob/living/silicon/robot/drone))
		return FALSE
	if(R.scrambledcodes)
		return FALSE
	if(!atoms_share_level(src, R))
		return FALSE
	return TRUE

/// If false, user cannot lockdown or detonate a specific cyborg
/obj/machinery/computer/robotics/proc/can_control(mob/user, mob/living/silicon/robot/R, telluserwhy = FALSE)
	if(!istype(user))
		return FALSE
	if(!console_shows(R))
		return FALSE
	if(isAI(user))
		if(R.connected_ai != user)
			if(telluserwhy)
				to_chat(user, "<span class='warning'>AIs can only control cyborgs which are linked to them.</span>")
			return FALSE
	if(isrobot(user))
		if(R != user)
			if(telluserwhy)
				to_chat(user, "<span class='warning'>Cyborgs cannot control other cyborgs.</span>")
			return FALSE
	return TRUE

/// Display hacking options when viewing console?
/obj/machinery/computer/robotics/proc/can_hack_any(mob/user)
	if(!istype(user))
		return FALSE
	if(user.can_admin_interact())
		return TRUE
	if(!isAI(user))
		return FALSE
	return (user.mind.special_role && user.mind.original == user)

/// Can user hack this specific borg?
/obj/machinery/computer/robotics/proc/can_hack(mob/user, mob/living/silicon/robot/R)
	if(!can_hack_any(user))
		return FALSE
	if(!istype(R))
		return FALSE
	if(R.emagged)
		return FALSE
	if(R.connected_ai != user)
		return FALSE
	return TRUE

/obj/machinery/computer/robotics/tgui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = TRUE, datum/tgui/master_ui = null, datum/tgui_state/state = GLOB.tgui_default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "RoboticsControlConsole",  name, 500, 460, master_ui, state)
		ui.open()

/obj/machinery/computer/robotics/tgui_data(mob/user)
	var/list/data = list()

	data["can_hack"] = can_hack_any(user)
	data["cyborgs"] = list()
	data["safety"] = safety
	for(var/mob/living/silicon/robot/R in GLOB.mob_list)
		if(!console_shows(R))
			continue
		var/area/A = get_area(R)
		var/turf/T = get_turf(R)
		var/list/cyborg_data = list(
			name = R.name,
			uid = R.UID(),
			locked_down = R.lockcharge,
			locstring = "[A.name] ([T.x], [T.y])",
			status = R.stat,
			health = round(R.health * 100 / R.maxHealth, 0.1),
			charge = R.cell ? round(R.cell.percent()) : null,
			cell_capacity = R.cell ? R.cell.maxcharge : null,
			module = R.module ? "[R.module.name] Module" : "No Module Detected",
			synchronization = R.connected_ai,
			is_hacked =  R.connected_ai && R.emagged,
			hackable = can_hack(user, R),
		)
		data["cyborgs"] += list(cyborg_data)
	data["show_detonate_all"] = (length(data["cyborgs"]) > 0 && !isAI(user))
	return data

/obj/machinery/computer/robotics/tgui_act(action, params)
	if(..())
		return
	. = FALSE
	if(!is_authenticated(usr))
		to_chat(usr, "<span class='warning'>Access denied.</span>")
		return
	switch(action)
		if("arm") // Arms the emergency self-destruct system
			if(issilicon(usr))
				to_chat(usr, "Access Denied (silicon detected)")
				return
			safety = !safety
			to_chat(usr, "<span class='notice'>You [safety ? "disarm" : "arm"] the emergency self destruct.</span>")
			. = TRUE
		if("nuke") // Destroys all accessible cyborgs if safety is disabled
			if(issilicon(usr))
				to_chat(usr, "Access Denied (silicon detected)")
				return
			if(safety)
				to_chat(usr, "Self-destruct aborted - safety active")
				return
			message_admins("<span class='notice'>[key_name_admin(usr)] detonated all cyborgs!</span>")
			log_game("\<span class='notice'>[key_name(usr)] detonated all cyborgs!</span>")
			for(var/mob/living/silicon/robot/R in GLOB.mob_list)
				if(istype(R, /mob/living/silicon/robot/drone))
					continue
				// Ignore antagonistic cyborgs
				if(R.scrambledcodes)
					continue
				to_chat(R, "<span class='danger'>Self-destruct command received.</span>")
				if(R.connected_ai)
					to_chat(R.connected_ai, "<br><br><span class='alert'>ALERT - Cyborg detonation detected: [R.name]</span><br>")
				R.self_destruct()
			. = TRUE
		if("killbot") // destroys one specific cyborg
			var/mob/living/silicon/robot/R = locateUID(params["uid"])
			if(!can_control(usr, R, TRUE))
				return
			if(R.mind && R.mind.special_role && R.emagged)
				to_chat(R, "<span class='userdanger'>Extreme danger!  Termination codes detected.  Scrambling security codes and automatic AI unlink triggered.</span>")
				R.ResetSecurityCodes()
				. = TRUE
				return
			var/turf/T = get_turf(R)
			message_admins("<span class='notice'>[key_name_admin(usr)] detonated [key_name_admin(R)] ([ADMIN_COORDJMP(T)])!</span>")
			log_game("\<span class='notice'>[key_name(usr)] detonated [key_name(R)]!</span>")
			to_chat(R, "<span class='danger'>Self-destruct command received.</span>")
			if(R.connected_ai)
				to_chat(R.connected_ai, "<br><br><span class='alert'>ALERT - Cyborg detonation detected: [R.name]</span><br>")
			R.self_destruct()
			. = TRUE
		if("stopbot") // lock or unlock the borg
			if(isrobot(usr))
				to_chat(usr, "<span class='danger'>Access Denied.</span>")
				return
			var/mob/living/silicon/robot/R = locateUID(params["uid"])
			if(!can_control(usr, R, TRUE))
				return
			message_admins("<span class='notice'>[ADMIN_LOOKUPFLW(usr)] [!R.lockcharge ? "locked down" : "released"] [ADMIN_LOOKUPFLW(R)]!</span>")
			log_game("[key_name(usr)] [!R.lockcharge ? "locked down" : "released"] [key_name(R)]!")
			R.SetLockdown(!R.lockcharge)
			to_chat(R, "[!R.lockcharge ? "<span class='notice'>Your lockdown has been lifted!" : "<span class='alert'>You have been locked down!"]</span>")
			if(R.connected_ai)
				to_chat(R.connected_ai, "[!R.lockcharge ? "<span class='notice'>NOTICE - Cyborg lockdown lifted</span>" : "<span class='alert'>ALERT - Cyborg lockdown detected</span>"]: <a href='?src=[R.connected_ai.UID()];track=[html_encode(R.name)]'>[R.name]</a></span><br>")
			. = TRUE
		if("magbot") // AIs hacking/emagging a borg
			var/mob/living/silicon/robot/R = locateUID(params["uid"])
			if(!can_hack(usr, R))
				return
			var/choice = input("Really hack [R.name]? This cannot be undone.") in list("Yes", "No")
			if(choice != "Yes")
				return
			log_game("[key_name(usr)] emagged [key_name(R)] using robotic console!")
			message_admins("<span class='notice'>[key_name_admin(usr)] emagged [key_name_admin(R)] using robotic console!</span>")
			R.emagged = TRUE
			to_chat(R, "<span class='notice'>Failsafe protocols overriden. New tools available.</span>")
			. = TRUE
