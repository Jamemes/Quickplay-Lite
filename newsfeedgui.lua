NewsFeedGui.MAX_NEWS = 50
NewsFeedGui.SUSTAIN_TIME = 7

Hooks:Add("LocalizationManagerPostInit", "Quickplay_Lite_loc", function(...)
	LocalizationManager:add_localized_strings({
		qpl_join = "Join",
		qpl_show_all = "Show all lobbies",
	})
	
	if Idstring("russian"):key() == SystemInfo:language():key() then
		LocalizationManager:add_localized_strings({
			qpl_join = "Присоединится",
			qpl_show_all = "Показать все лобби",
		})
	end
end)

local function make_fine_text(text)
	local x, y, w, h = text:text_rect()

	text:set_size(w, h)

	return x, y, w, h
end

function NewsFeedGui:update(t, dt)
	if not self._lobbies then
		return
	end

	if self._news then
		local color = math.lerp(tweak_data.screen_colors.button_stage_2, tweak_data.screen_colors.button_stage_3, (1 + math.sin(t * 360)) / 2)
		self._title_panel:child("title"):set_color(self._mouse_over and tweak_data.screen_colors.button_stage_2 or color)
		
		local title_announcement = self._panel:child("title_announcement")
		title_announcement:set_visible(#self._lobbies > 0 or self._news.i > 0)
		title_announcement:set_text(string.format("%s (%s/%s)", managers.localization:to_upper_text("cn_menu_num_players_offline"), self._news.i, #self._lobbies))

		local announcement_legend = self._panel:child("announcement_legend")
		announcement_legend:set_visible(self._mouse_over)
		announcement_legend:set_text(string.format("[MOUSE 0] %s\n[MOUSE 2] %s\n[MOUSE 1] %s", managers.localization:text("qpl_join"), managers.localization:text("menu_lobby_filters"), managers.localization:text("qpl_show_all")))
		announcement_legend:set_left(self._title_panel:right() + 10)
		announcement_legend:set_center_y(self._title_panel:center_y())
		
		if self._next then
			self._next = nil
			self._news.i = self._news.i + 1
			if self._news.i > #self._lobbies then
				self._news.i = #self._lobbies > 0 and 1 or 0
			end
			
			if #self._lobbies > 0 then
				local title_panel_text = table.concat(self._lobbies[self._news.i].lobby_info, "\n")
				self._title_panel:child("title"):set_text(utf8.to_upper(title_panel_text))
				local _, _, w, h = self._title_panel:child("title"):text_rect()
				self._title_panel:child("title"):set_h(h)
				self._title_panel:set_w(w + 10)
				self._title_panel:set_h(h)
				self._title_panel:set_left(self._panel:w())
				self._title_panel:set_top(title_announcement:bottom())
				self._present_t = t + self.PRESENT_TIME
			end
		end

		if self._present_t then
			self._title_panel:set_left(0 - (managers.gui_data:safe_scaled_size().x + self._title_panel:w()) * ((self._present_t - t) / self.PRESENT_TIME))
			if t > self._present_t then
				self._title_panel:set_left(0)
				self._present_t = nil
				
				local no_lobbies = #self._lobbies == 0 and self._news.i > 0
				local new_lobbies = #self._lobbies > 0 and self._news.i == 0
				local sustain = no_lobbies and 0 or new_lobbies and 0 or self.SUSTAIN_TIME
				self._sustain_t = t + sustain
			end
		end

		if self._sustain_t and t > self._sustain_t then
			self._sustain_t = nil
			self._remove_t = t + self.REMOVE_TIME
		end

		if self._remove_t then
			self._title_panel:set_left(0 - (managers.gui_data:safe_scaled_size().x + self._title_panel:w()) * (1 - (self._remove_t - t) / self.REMOVE_TIME))
			if t > self._remove_t then
				self:make_news_request(true)
				self._title_panel:set_left(0 - (managers.gui_data:safe_scaled_size().x + self._title_panel:w()))
				self._remove_t = nil
				self._next = true
			end
		end
	end
end

function NewsFeedGui:_create_gui()
	local size = managers.gui_data:scaled_size()
	self._panel = self._ws:panel():panel({
		name = "main",
		w = size.width / 2,
		h = 22
	})
	self._panel:bitmap({
		visible = false,
		name = "bg_bitmap",
		texture = "guis/textures/textboxbg",
		layer = 0,
		color = Color.black,
		w = self._panel:w(),
		h = self._panel:h()
	})
	
	self._panel:text({
		visible = false,
		rotation = 360,
		name = "title_announcement",
		text = managers.localization:to_upper_text("cn_menu_num_players_offline"),
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_small_font_size,
		align = "left",
		halign = "left",
		vertical = "top",
		hvertical = "top",
		color = Color.white
	})
	
	self._panel:text({
		visible = false,
		rotation = 360,
		name = "announcement_legend",
		text = "",
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_small_font_size / 1.5,
		align = "left",
		halign = "left",
		vertical = "top",
		hvertical = "top",
		color = Color.white:with_alpha(0.5)
	})
	
	self._title_panel = self._panel:panel({
		name = "title_panel",
		layer = 1
	})
	
	self._title_panel:text({
		y = 12,
		rotation = 360,
		name = "title",
		text = "",
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
		align = "center",
		halign = "center",
		vertical = "bottom",
		hvertical = "bottom",
		color = Color(0.75, 0.75, 0.75)
	})
	self._title_panel:set_right(-10)
end

function NewsFeedGui:make_news_request(push)
	local function f(info)
		if not info.room_list then
			return
		end
		
		managers.network.matchmake:search_lobby_done()
		
		local quick = Global.crimenet and Global.crimenet.quickplay
		local room_list = info.room_list
		local attribute_list = info.attribute_list
		
		local lobbies = {}
		for i, room in ipairs(room_list) do
			local attributes_numbers = attribute_list[i].numbers
			local job_id = tweak_data.narrative:get_job_name_from_index(math.floor(attributes_numbers[1] / 1000))
			local state_string_id = tweak_data:index_to_server_state(attributes_numbers[4])
			local state_name = state_string_id and managers.localization:text("menu_lobby_server_state_" .. state_string_id) or "UNKNOWN"
			local job_tweak = job_id and tweak_data.narrative:job_data(job_id)
			local is_professional = job_tweak and job_tweak.professional
			local prof = is_professional and string.format(" (%s)", managers.localization:to_upper_text("cn_menu_pro_job")) or ""
			local job_name = job_tweak and managers.localization:to_upper_text(job_tweak.name_id) .. prof
			local difficulty = attributes_numbers[2] - 2 > 0 and string.rep("", attributes_numbers[2] - 2)
	
			lobbies[i] = {
				room_id = tostring(room.room_id),
				lobby_info = {}
			}

			table.insert(lobbies[i].lobby_info, tostring(room.owner_name))
			table.insert(lobbies[i].lobby_info, job_name)
			table.insert(lobbies[i].lobby_info, tostring(state_name .. string.format(" [%s/4]", attributes_numbers[5])))
			table.insert(lobbies[i].lobby_info, difficulty or nil)
		end
		
		local function shuffle(t)
			for i = 1, #t - 1 do
				local swap_index = math.random(i, #t)
				local temp = t[i]
				t[i] = t[swap_index]
				t[swap_index] = temp
			end
			return t
		end
		
		self._lobbies = shuffle(lobbies)

		if not push then
			self._news = {i = 0}
			self._next = true
		end
	end

	if managers.network.matchmake and managers.network.matchmake.load_user_filters then
		managers.network.matchmake:load_user_filters()
	end

	managers.network.matchmake:register_callback("search_lobby", f)
	managers.network.matchmake:search_lobby(managers.network.matchmake:search_friends_only())
end

function NewsFeedGui:mouse_pressed(button, x, y)
	if not self._news then
		return
	end

	if button == Idstring("0") and self._title_panel:inside(x, y) then
		if self._lobbies[self._news.i] then
			managers.network.matchmake:join_server_with_check(self._lobbies[self._news.i].room_id)
		end
		
		return true
	elseif button == Idstring("1") and self._title_panel:inside(x, y) then
		if self._lobbies then
			local num_lobbies = #self._lobbies
			for i, lobby in pairs(self._lobbies) do
				local dialog_data = {
					id = "quick_lobby_dialog" .. i,
					text = table.concat(lobby.lobby_info, "\n")
				}
				local join_button = {text = managers.localization:text("cn_menu_accept_contract"), callback_func = function()
					managers.system_menu:force_close_all()
					managers.network.matchmake:join_server_with_check(lobby.room_id)
				end}
				local ok_button = {text = managers.localization:text("menu_back"), cancel_button = true}
				local cancel_all = {text = managers.localization:text("dialog_cancel"), callback_func = function()
					managers.system_menu:force_close_all()
				end}
				dialog_data.button_list = {
					join_button,
					{},
					ok_button,
					cancel_all
				}
				managers.system_menu:show(dialog_data)
			end
		end
		
		return true
	elseif button == Idstring("2") then
		managers.menu:open_node("crimenet_filters", {})
		
		if managers.menu_component._new_heists_gui then
			managers.menu_component._new_heists_gui.set_bar_width = function() end
		end

		return true
	end
end

function NewsFeedGui:mouse_moved(x, y)
	local inside = self._title_panel:inside(x, y)
	self._mouse_over = inside
	return inside, inside and "link"
end