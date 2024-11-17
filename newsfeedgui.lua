NewsFeedGui.MAX_NEWS = 50
NewsFeedGui.SUSTAIN_TIME = 7
function NewsFeedGui:update(t, dt)
	if not self._titles then
		return
	end
	if self._news then
		local color = math.lerp(tweak_data.screen_colors.button_stage_2, tweak_data.screen_colors.button_stage_3, (1 + math.sin(t * 360)) / 2)
		self._panel:child("title_announcement"):set_text(string.format("%s (%s/%s)", managers.localization:to_upper_text("cn_menu_num_players_offline"), self._news.i, #self._titles))
		self._title_panel:child("title"):set_color(self._mouse_over and tweak_data.screen_colors.button_stage_2 or color)
		if self._next then
			self._next = nil
			self._news.i = self._news.i + 1
			if self._news.i > #self._titles then
				self._news.i = #self._titles > 0 and 1 or 0
			end
			self._title_panel:child("title"):set_text(utf8.to_upper(self._titles[self._news.i]))
			local _, _, w, h = self._title_panel:child("title"):text_rect()
			self._title_panel:child("title"):set_h(h)
			self._title_panel:set_w(w + 10)
			self._title_panel:set_h(h)
			self._title_panel:set_left(self._panel:w())
			self._title_panel:set_top(self._panel:child("title_announcement"):bottom())
			self._present_t = t + self.PRESENT_TIME
		end
		if self._present_t then
			self._title_panel:set_left(0 - (managers.gui_data:safe_scaled_size().x + self._title_panel:w()) * ((self._present_t - t) / self.PRESENT_TIME))
			if t > self._present_t then
				self._title_panel:set_left(0)
				self._present_t = nil
				
				local no_lobbies = #self._titles == 0 and self._news.i > 0
				local new_lobbies = #self._titles > 0 and self._news.i == 0
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
		
		local game_list = {}
		local join_ids = {}
		
		for i, room in ipairs(room_list) do
			local attributes_numbers = attribute_list[i].numbers
			local job_id = tweak_data.narrative:get_job_name_from_index(math.floor(attributes_numbers[1] / 1000))
			local difficulty = tweak_data:index_to_difficulty(attributes_numbers[2])
			local state_string_id = tweak_data:index_to_server_state(attributes_numbers[4])
			local state_name = state_string_id and managers.localization:text("menu_lobby_server_state_" .. state_string_id) or "UNKNOWN"
			local num_plrs = attributes_numbers[5]
			
			local job_tweak = job_id and tweak_data.narrative:job_data(job_id)
			local is_professional = job_tweak and job_tweak.professional
			local prof = is_professional and string.format(" (%s)", managers.localization:to_upper_text("cn_menu_pro_job")) or ""
			
			game_list[i] = string.format("%s\n%s\n%s [%s/4]\n%s", tostring(room.owner_name), job_tweak and managers.localization:to_upper_text(job_tweak.name_id) .. prof or "", state_name, num_plrs, attributes_numbers[2] - 2 > 0 and string.rep("", attributes_numbers[2] - 2) or "")
			join_ids[i] = tostring(room.room_id)
		end

		self._titles = game_list
		self._links = join_ids

		if not push then
			self._news = {i = 0}
			self._next = true
		end
		
		local current_server = 0
		if self._news then
			current_server = self._news.i
		end
		
		self._panel:child("title_announcement"):set_visible(#self._titles > 0 or current_server > 0)
	end
	
	managers.network.matchmake:register_callback("search_lobby", f)
	managers.network.matchmake:search_lobby()
end

function NewsFeedGui:mouse_pressed(button, x, y)
	if not self._news then
		return
	end
	if button == Idstring("0") and self._title_panel:inside(x, y) then
		if self._links[self._news.i] then
			managers.network.matchmake:join_server_with_check(self._links[self._news.i])
		end
		return true
	end
end

function NewsFeedGui:mouse_moved(x, y)
	local inside = self._title_panel:inside(x, y)
	self._mouse_over = inside
	return inside, inside and "link"
end