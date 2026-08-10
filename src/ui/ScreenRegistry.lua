return function(deps)
  local Time = assert(deps.Time, "ScreenRegistry needs Time")

  local Registry = {}
  local IDS = {
    root = "SavestatesRoot",
    history = "SavestatesHistory",
    actions = "SavestatesActions",
    details = "SavestatesDetails",
    slots = "SavestatesSlots",
    slotActions = "SavestatesSlotActions",
    pinPicker = "SavestatesPinPicker",
    rename = "SavestatesRename",
    overwriteConfirm = "SavestatesOverwriteConfirm",
    deleteConfirm = "SavestatesDeleteConfirm",
    settings = "SavestatesSettings",
  }

  local function truncate(text, maximum)
    text = tostring(text or "----")
    if #text <= maximum then return text end
    return text:sub(1, maximum - 1) .. "."
  end

  local function dispatch(item, menu)
    if item and item.onSelect then item.onSelect(item, menu) end
  end

  local function isTitleContext(opts)
    return type(opts) == "table" and opts.context == "title"
  end

  local function closeMenus(current, parents)
    if current and current.close then current:close() end
    for _, menu in ipairs(parents or {}) do
      if menu and menu.close then menu:close() end
    end
  end

  local function stateLabel(metadata)
    return truncate(metadata.label or metadata.locationName
      or metadata.locationId or metadata.id, 14)
  end

  local function upperValue(value, maximum)
    return truncate(tostring(value or "----"):upper(), maximum or 12)
  end

  local function appendPreview(items, preview)
    if type(preview) ~= "table" then return end
    items[#items + 1] = { label = "PLAY TIME", right = Time.playTime(preview.playTime) }
    items[#items + 1] = { label = "BADGES", right = ("%d/%d"):format(
      tonumber(preview.badgeCount) or 0, tonumber(preview.badgeTotal) or 0) }
    for _, mon in ipairs(preview.party or {}) do
      items[#items + 1] = {
        label = truncate(mon.name, 12),
        right = ("L%-2d %d/%d"):format(mon.level, mon.hp, mon.maxHp),
      }
    end
  end

  function Registry.install(mod, service, clock)
    clock = clock or os.time

    local function method(opts, activeName, titleName)
      return service[isTitleContext(opts) and titleName or activeName]
    end

    local function inspect(row, game, opts)
      local metadata = type(row) == "table" and row.metadata or nil
      local inspectState = method(opts, "inspectState", "titleInspectState")
      if type(metadata) ~= "table" or type(inspectState) ~= "function" then
        return row or { metadata = {} }
      end
      local resolved, code, message = inspectState(service, game, metadata.id)
      if resolved then return resolved end
      return {
        metadata = metadata,
        available = false,
        status = code,
        message = message,
        preview = metadata.preview,
      }
    end

    local function refreshRoot(game, root, opts)
      if type(root) ~= "table" or type(root.items) ~= "table" then return false end
      local summaryFor = method(opts, "summary", "titleSummary")
      local summary = type(summaryFor) == "function" and summaryFor(service, game) or nil
      if not summary then return false end
      for _, item in ipairs(root.items) do
        if item.label == "QUICK SAVES" then
          item.right = tostring(summary.quickCount)
        elseif item.label == "AUTO SAVES" then
          item.right = tostring(summary.autoCount)
        elseif item.label == "SAVE SLOTS" then
          item.right = ("%d/%d"):format(summary.slotCount, summary.slotCapacity)
        end
      end
      return true
    end

    mod.content.screens:register(IDS.root, {
      new = function(game, opts)
        opts = opts or {}
        local summaryFor = method(opts, "summary", "titleSummary")
        local summary, code
        if type(summaryFor) == "function" then summary, code = summaryFor(service, game) end
        local menu
        if not summary then
          return mod.ui.ListMenu.new(game, "SAVE STATES", {
            { label = "STATE DATA ERROR", right = truncate(code, 6) },
          }, { onChoose = dispatch })
        end
        local items = {
          { label = "QUICK SAVES", right = tostring(summary.quickCount),
            onSelect = function()
              mod.ui.push(game, IDS.history, {
                class = "quick", parent = menu, context = opts.context,
              })
            end },
          { label = "AUTO SAVES", right = tostring(summary.autoCount),
            onSelect = function()
              mod.ui.push(game, IDS.history, {
                class = "auto", parent = menu, context = opts.context,
              })
            end },
          { label = "SAVE SLOTS",
            right = ("%d/%d"):format(summary.slotCount, summary.slotCapacity),
            onSelect = function()
              mod.ui.push(game, IDS.slots, { parent = menu, context = opts.context })
            end },
        }
        if summary.undoAvailable then
          items[#items + 1] = { label = "UNDO LAST LOAD", onSelect = function()
            menu:close()
            service:undoLastLoad(game)
          end }
        end
        items[#items + 1] = { label = "SETTINGS", onSelect = function()
          mod.ui.push(game, IDS.settings, { parent = menu, context = opts.context })
        end }
        menu = mod.ui.ListMenu.new(game, "SAVE STATES", items, {
          onChoose = dispatch,
          pageJump = true,
        })
        return menu
      end,
    })

    mod.content.screens:register(IDS.history, {
      new = function(game, opts)
        opts = opts or {}
        local class = opts.class == "auto" and "auto" or "quick"
        local listStates = method(opts, "listStates", "titleListStates")
        local rows, code
        if type(listStates) == "function" then rows, code = listStates(service, game, class) end
        local title = class == "auto" and "AUTO SAVES" or "QUICK SAVES"
        local menu
        local items = {}
        if not rows then
          items[1] = { label = "STATE DATA ERROR", right = truncate(code, 6) }
        elseif #rows == 0 then
          items[1] = { label = class == "auto"
            and "NO AUTO SAVES YET." or "NO QUICK SAVES YET." }
        else
          for _, row in ipairs(rows) do
            items[#items + 1] = {
              label = stateLabel(row.metadata),
              right = row.available == false and "BAD" or Time.relative(row.metadata.createdAt, clock()),
              value = row,
              onSelect = function(item)
                mod.ui.push(game, IDS.actions, {
                  row = item.value,
                  parents = { menu, opts.parent },
                  context = opts.context,
                })
              end,
            }
          end
        end
        menu = mod.ui.ListMenu.new(game, title, items, {
          onChoose = dispatch,
          pageJump = true,
          keyRepeat = true,
        })
        return menu
      end,
    })

    mod.content.screens:register(IDS.actions, {
      new = function(game, opts)
        opts = opts or {}
        local row = inspect(opts.row, game, opts)
        local metadata = row.metadata or {}
        local menu
        local items = {}
        if row.available then
          items[#items + 1] = { label = "LOAD", onSelect = function()
            closeMenus(menu, opts.parents)
            local loadState = method(opts, "loadState", "resumeTitleState")
            if type(loadState) == "function" then loadState(service, game, metadata.id) end
          end }
          items[#items + 1] = { label = "PIN TO SLOT", onSelect = function()
            mod.ui.push(game, IDS.pinPicker, {
              sourceId = metadata.id,
              action = menu,
              root = opts.parents and opts.parents[2],
              context = opts.context,
            })
          end }
        end
        items[#items + 1] = { label = "DETAILS", onSelect = function()
          mod.ui.push(game, IDS.details, {
            row = row, parent = menu, context = opts.context,
          })
        end }
        items[#items + 1] = { label = "DELETE", onSelect = function()
          mod.ui.push(game, IDS.deleteConfirm, {
            target = "state",
            id = metadata.id,
            action = menu,
            history = opts.parents and opts.parents[1],
            root = opts.parents and opts.parents[2],
            context = opts.context,
          })
        end }
        items[#items + 1] = { label = "CANCEL", onSelect = function()
          menu:close()
        end }
        menu = mod.ui.ListMenu.new(game, stateLabel(metadata), items, {
          onChoose = dispatch,
          pageJump = true,
        })
        menu.index = 1
        return menu
      end,
    })

    mod.content.screens:register(IDS.details, {
      new = function(game, opts)
        opts = opts or {}
        local row = inspect(opts.row, game, opts)
        local metadata = row.metadata or {}
        local status = row.available and
          ((type(row.warnings) == "table" and next(row.warnings)) and "WARN" or "OK")
          or upperValue(row.status, 10)
        local items = {
          { label = "LOCATION", right = truncate(
              metadata.locationName or metadata.locationId, 12) },
          { label = "TRIGGER", right = upperValue(
              metadata.trigger and metadata.trigger:gsub("_", " "), 12) },
          { label = "CREATED", right = Time.relative(metadata.createdAt, clock()) },
          { label = "KIND", right = upperValue(metadata.stateKind, 12) },
          { label = "STATUS", right = status },
        }
        appendPreview(items, row.preview or metadata.preview)
        return mod.ui.ListMenu.new(game, "STATE DETAILS", items, {
          onChoose = dispatch,
          pageJump = true,
          keyRepeat = true,
        })
      end,
    })

    mod.content.screens:register(IDS.pinPicker, {
      new = function(game, opts)
        opts = opts or {}
        local listSlots = method(opts, "listSlots", "titleListSlots")
        local rows = type(listSlots) == "function" and listSlots(service, game) or {}
        local menu
        local items = {}
        for slot = 1, 10 do
          local row = rows[slot] or { slot = slot, occupied = false }
          local function pin()
            local pinToSlot = method(opts, "pinToSlot", "titlePinToSlot")
            local pinned = type(pinToSlot) == "function"
              and pinToSlot(service, game, opts.sourceId, slot)
            if pinned then
              refreshRoot(game, opts.root, opts)
              menu:close()
              if opts.action and opts.action.close then opts.action:close() end
            end
          end
          items[#items + 1] = {
            label = ("SLOT %d"):format(slot),
            right = row.occupied and truncate(row.metadata.label
              or row.metadata.locationName, 12) or "EMPTY",
            onSelect = function()
              if row.occupied then
                mod.ui.push(game, IDS.overwriteConfirm, { confirm = pin })
              else
                pin()
              end
            end,
          }
        end
        menu = mod.ui.ListMenu.new(game, "PIN TO SLOT", items, {
          onChoose = dispatch,
          pageJump = true,
        })
        return menu
      end,
    })

    mod.content.screens:register(IDS.slots, {
      new = function(game, opts)
        opts = opts or {}
        local listSlots = method(opts, "listSlots", "titleListSlots")
        local rows, code
        if type(listSlots) == "function" then rows, code = listSlots(service, game) end
        if not rows then
          return mod.ui.ListMenu.new(game, "SAVE SLOTS", {
            { label = "STATE DATA ERROR", right = truncate(code, 6) },
          }, { onChoose = dispatch })
        end
        local menu
        local items = {}
        for slot = 1, 10 do
          local row = rows[slot]
          items[slot] = {
            label = ("SLOT %d"):format(slot),
            right = row.occupied and truncate(row.metadata.label
              or row.metadata.locationName, 12) or "EMPTY",
            value = row,
            onSelect = function(item)
              mod.ui.push(game, IDS.slotActions, {
                row = item.value,
                parents = { menu, opts.parent },
                slotMenu = menu,
                context = opts.context,
              })
            end,
          }
        end
        menu = mod.ui.ListMenu.new(game, "SAVE SLOTS", items, {
          onChoose = dispatch,
          pageJump = true,
          keyRepeat = true,
        })
        return menu
      end,
    })

    mod.content.screens:register(IDS.slotActions, {
      new = function(game, opts)
        opts = opts or {}
        local row = opts.row or { slot = 1, occupied = false }
        if row.occupied then row = inspect(row, game, opts) end
        local slot = row.slot
        local menu
        local items = {}
        local title = isTitleContext(opts)
        local function saveHere()
          closeMenus(menu, opts.parents)
          service:saveSlot(game, slot)
        end
        if not row.occupied then
          if not title then
            items[#items + 1] = { label = "SAVE HERE", onSelect = saveHere }
          end
        else
          if row.available then
            items[#items + 1] = { label = "LOAD", onSelect = function()
              closeMenus(menu, opts.parents)
              local loadSlot = title and service.resumeTitleState or service.loadSlot
              if type(loadSlot) == "function" then
                loadSlot(service, game, title and row.metadata.id or slot)
              end
            end }
          end
          if not title then
            items[#items + 1] = { label = "OVERWRITE", onSelect = function()
              mod.ui.push(game, IDS.overwriteConfirm, { confirm = saveHere })
            end }
          end
          items[#items + 1] = { label = "RENAME", onSelect = function()
            mod.ui.push(game, IDS.rename, {
              slot = slot,
              action = menu,
              slotMenu = opts.slotMenu,
              context = opts.context,
            })
          end }
          items[#items + 1] = { label = "DETAILS", onSelect = function()
            mod.ui.push(game, IDS.details, {
              row = row, parent = menu, context = opts.context,
            })
          end }
          items[#items + 1] = { label = "DELETE", onSelect = function()
            mod.ui.push(game, IDS.deleteConfirm, {
              target = "slot",
              slot = slot,
              id = row.metadata and row.metadata.id,
              action = menu,
              slotMenu = opts.slotMenu,
              root = opts.parents and opts.parents[2],
              context = opts.context,
            })
          end }
        end
        items[#items + 1] = { label = "CANCEL", onSelect = function()
          menu:close()
        end }
        menu = mod.ui.ListMenu.new(game, ("SLOT %d"):format(slot), items, {
          onChoose = dispatch,
        })
        return menu
      end,
    })

    mod.content.screens:register(IDS.rename, {
      new = function(game, opts)
        opts = opts or {}
        return mod.ui.NamingScreen.new(game, {
          title = "SLOT NAME?",
          maxLen = 12,
          onDone = function(name)
            if name == "" then return end
            local renameSlot = method(opts, "renameSlot", "titleRenameSlot")
            local renamed = type(renameSlot) == "function"
              and renameSlot(service, game, opts.slot, name)
            if renamed and opts.slotMenu and opts.slotMenu.items[opts.slot] then
              local item = opts.slotMenu.items[opts.slot]
              item.right = truncate(renamed.metadata.label, 12)
              item.value = {
                slot = opts.slot,
                occupied = true,
                available = true,
                status = "compatible",
                metadata = renamed.metadata,
              }
            end
            if renamed and opts.action and opts.action.close then opts.action:close() end
          end,
        })
      end,
    })

    mod.content.screens:register(IDS.overwriteConfirm, {
      new = function(game, opts)
        opts = opts or {}
        return mod.ui.TextBox.new(game, "OVERWRITE THIS SLOT?", nil, {
          defaultNo = true,
          choice = function(yes)
            if yes and type(opts.confirm) == "function" then opts.confirm() end
          end,
        })
      end,
    })

    mod.content.screens:register(IDS.deleteConfirm, {
      new = function(game, opts)
        opts = opts or {}
        local isSlot = opts.target == "slot"
        return mod.ui.TextBox.new(game,
          isSlot and "DELETE THIS SLOT?" or "DELETE THIS STATE?", nil, {
            defaultNo = true,
            choice = function(yes)
              if not yes then return end
              local deleted
              if isSlot then
                if isTitleContext(opts) then
                  deleted = service:titleDeleteState(game, opts.id)
                else
                  deleted = service:deleteSlot(game, opts.slot)
                end
              else
                local deleteState = method(opts, "deleteState", "titleDeleteState")
                deleted = type(deleteState) == "function"
                  and deleteState(service, game, opts.id)
              end
              if not deleted then return end
              if opts.action and opts.action.close then opts.action:close() end
              if isSlot then
                local item = opts.slotMenu and opts.slotMenu.items[opts.slot]
                if item then
                  item.right = "EMPTY"
                  item.value = { slot = opts.slot, occupied = false }
                end
              elseif opts.history and opts.history.removeCurrent then
                opts.history:removeCurrent()
              end
              refreshRoot(game, opts.root, opts)
            end,
          })
      end,
    })

    mod.content.screens:register(IDS.settings, {
      new = function(game)
        local function onOff(value) return value and "ON" or "OFF" end
        local items = {
          { label = "QUICK HISTORY", right = tostring(mod.options:get("quick_history")) },
          { label = "AUTO HISTORY", right = tostring(mod.options:get("auto_history")) },
          { label = "LOCATION ENTRY", right = onOff(mod.options:get("auto_location")) },
          { label = "TRAINER BATTLE", right = onOff(
              mod.options:get("auto_trainer_battle")) },
          { label = "WILD BATTLE", right = onOff(
              mod.options:get("auto_wild_battle")) },
          { label = "AFTER BATTLE", right = onOff(mod.options:get("auto_after_battle")) },
          { label = "BEFORE WARP", right = onOff(mod.options:get("auto_before_warp")) },
          { label = "SAVE POPUPS", right = onOff(mod.options:get("save_notifications")) },
          { label = "LOAD POPUPS", right = onOff(mod.options:get("load_notifications")) },
          { label = "DEBUG TIMINGS", right = onOff(mod.options:get("debug_logging")) },
        }
        return mod.ui.ListMenu.new(game, "STATE SETTINGS", items, {
          onChoose = function(_, menu) menu:close() end,
          footer = "CHANGE IN MODS > SAVE STATES",
          pageJump = true,
          keyRepeat = true,
        })
      end,
    })

    local out = {}
    for key, value in pairs(IDS) do out[key] = value end
    return out
  end

  return Registry
end
