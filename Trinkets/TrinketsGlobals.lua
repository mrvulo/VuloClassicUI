-- Backdrop tables plus a polyfill of BackdropTemplateMixin for pre-9.x clients.
Trinkets_BACKDROP_16_16_4444 = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true,
	tileEdge = true,
	tileSize = 16,
	edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
Trinkets_BACKDROP_16 = {
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 16,
}
Trinkets_SLIDER_BACKDROP = {
	bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
	edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
	tile = true,
	tileEdge = true,
	tileSize = 8,
	edgeSize = 8,
	insets = { left = 3, right = 3, top = 6, bottom = 6 },
}

local BackdropTemplatePolyfillMixin = {}

function BackdropTemplatePolyfillMixin:OnBackdropLoaded()
	if not self.backdropInfo then
		return
	end

	if not self.backdropInfo.edgeFile and not self.backdropInfo.bgFile then
		self.backdropInfo = nil
		return
	end

	self:ApplyBackdrop()

	if self.backdropColor then
		local r, g, b = self.backdropColor:GetRGB()
		self:SetBackdropColor(r, g, b, self.backdropColorAlpha or 1)
	end

	if self.backdropBorderColor then
		local r, g, b = self.backdropBorderColor:GetRGB()
		self:SetBackdropBorderColor(r, g, b, self.backdropBorderColorAlpha or 1)
	end

	if self.backdropBorderBlendMode then
		self:SetBackdropBorderBlendMode(self.backdropBorderBlendMode)
	end
end

function BackdropTemplatePolyfillMixin:OnBackdropSizeChanged()
	if self.backdropInfo then
		self:SetupTextureCoordinates()
	end
end

function BackdropTemplatePolyfillMixin:ApplyBackdrop()
	self:SetBackdrop(self.backdropInfo)
end

function BackdropTemplatePolyfillMixin:ClearBackdrop()
	self:SetBackdrop(nil)
	self.backdropInfo = nil
end

function BackdropTemplatePolyfillMixin:GetEdgeSize()
	-- Errors without a backdrop assigned, matching 9.x behaviour.
	return self.backdropInfo.edgeSize or 39
end

function BackdropTemplatePolyfillMixin:HasBackdropInfo(backdropInfo)
	return self.backdropInfo == backdropInfo
end

function BackdropTemplatePolyfillMixin:SetBorderBlendMode()
	-- No-op: pre-9.x has no backdrop border blend mode.
end

function BackdropTemplatePolyfillMixin:SetupPieceVisuals()
	-- No-op: backdrop internals are handled C-side pre-9.x.
end

function BackdropTemplatePolyfillMixin:SetupTextureCoordinates()
	-- No-op: texture coordinates are handled C-side pre-9.x.
end

TrinketsBackdropTemplateMixin = CreateFromMixins(BackdropTemplateMixin or BackdropTemplatePolyfillMixin)
