local window = require('cmp.utils.window')
local config = require('cmp.config')

---@class cmp.DocsView
---@field public window cmp.Window
---@field entry cmp.Entry
local docs_view = {}

---Create new floating window module
docs_view.new = function()
  local self = setmetatable({}, { __index = docs_view })
  self.entry = nil
  self.window = window.new()
  self.window:option('conceallevel', 2)
  self.window:option('concealcursor', 'n')
  self.window:option('foldenable', false)
  self.window:option('linebreak', true)
  self.window:option('scrolloff', 0)
  self.window:option('showbreak', 'NONE')
  self.window:option('wrap', true)
  self.window:buffer_option('filetype', 'cmp_docs')
  self.window:buffer_option('buftype', 'nofile')
  return self
end

---Open documentation window
---@param e cmp.Entry
---@param view cmp.WindowStyle
docs_view.open = function(self, e, view)
  local documentation = config.get().window.documentation
  if not documentation then
    return
  end

  if not e or not view then
    return self:close()
  end

  local border_info = window.get_border_info({ style = documentation })
  local right_space = vim.o.columns - (view.col + view.width) - 1
  local left_space = view.col - 1
  local max_width = math.max(left_space, right_space)
  if documentation.max_width > 0 then
    max_width = math.min(documentation.max_width, max_width)
  end

  local documents
  local bufnr
  local opts = { max_width = max_width - border_info.horiz }
  local lang_for_ft = vim.treesitter.language.get_lang(e.context.filetype) or ''
  local has_ts_parser = vim.treesitter.language.add(lang_for_ft)
  -- Update buffer content if needed.
  if not self.entry or e.id ~= self.entry.id then
    documents = e:get_documentation()
    if #documents == 0 then
      return self:close()
    end

    self.entry = e
    bufnr = self.window:get_buffer()
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd([[syntax clear]])
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
    end)
    if not has_ts_parser then
      if documentation.max_height > 0 then
        opts.max_height = documentation.max_height
      end
      vim.lsp.util.stylize_markdown(bufnr, documents, opts)
    end
  end

  -- Set buffer as not modified, so it can be removed without errors
  vim.api.nvim_set_option_value('modified', false, { buf = bufnr })

  -- Calculate window size.
  if documentation.max_height > 0 then
    opts.max_height = documentation.max_height - border_info.vert
  end

  local width, height = vim.lsp.util._make_floating_popup_size(documents, opts)
  if width <= 0 or height <= 0 then
    return self:close()
  end

  if has_ts_parser then
    local contents = vim.lsp.util._normalize_markdown(documents, { width = width })
    if not bufnr then
      bufnr = self.window:get_buffer()
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, contents)
    vim.treesitter.start(bufnr, 'markdown')
  end

  -- Calculate window position.
  local right_col = view.col + view.width
  local left_col = view.col - width - border_info.horiz
  local col, left
  if right_space >= width and left_space >= width then
    if right_space < left_space then
      col = left_col
      left = true
    else
      col = right_col
    end
  elseif right_space >= width then
    col = right_col
  elseif left_space >= width then
    col = left_col
    left = true
  else
    return self:close()
  end

  -- Render window.
  self.window:option('winblend', documentation.winblend)
  self.window:option('winhighlight', documentation.winhighlight)
  local style = {
    relative = 'editor',
    style = 'minimal',
    width = width,
    height = height,
    row = view.row,
    col = col,
    border = documentation.border,
    zindex = documentation.zindex or 50,
  }
  self.window:open(style)

  -- Correct left-col for scrollbar existence.
  if left then
    style.col = style.col - self.window:info().scrollbar_offset
    self.window:open(style)
  end

  if self.window.win then
    -- Highlight separators
    vim.api.nvim_win_call(self.window.win, function()
      vim.fn.clearmatches(self.window.win)
      vim.fn.matchadd('CmpDocSeparator', '^────*')
    end)

    -- Adjust height after treesitter (which can conceal lines) or stylize_markdown
    local conceal_height = vim.api.nvim_win_text_height(self.window.win, {}).all
    if conceal_height < vim.api.nvim_win_get_height(self.window.win) then
      vim.api.nvim_win_set_height(self.window.win, conceal_height)
    end
  end
end

---Close floating window
docs_view.close = function(self)
  self.window:close()
  self.entry = nil
end

docs_view.scroll = function(self, delta)
  if self:visible() then
    local info = vim.fn.getwininfo(self.window.win)[1] or {}
    local top = info.topline or 1
    top = top + delta
    top = math.max(top, 1)
    top = math.min(top, self.window:get_content_height() - info.height + 1)

    vim.defer_fn(function()
      vim.api.nvim_buf_call(self.window:get_buffer(), function()
        vim.api.nvim_command('normal! ' .. top .. 'zt')
        self.window:update()
      end)
    end, 0)
  end
end

docs_view.visible = function(self)
  return self.window:visible()
end

return docs_view
