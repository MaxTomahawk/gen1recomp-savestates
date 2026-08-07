return function(deps)
  local Time = assert(deps.Time, "ScreenRegistry needs Time")

  local Registry = {}
  local IDS = {
    root = "SavestatesRoot",
    history = "SavestatesHistory",
    actions = "SavestatesActions",
    slots = "SavestatesSlots",
    slotActions = "SavestatesSlotActions",
    pinPicker = "SavestatesPinPicker",
    rename = "SavestatesRename",
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

  function Registry.install(mod, service, clock)
    clock = clock or os.time

    mod.content.screens:register(IDS.root, {
      new = function(game)
        local summary, code = service:summary(game)
        local menu
        if not summary then
          return mod.ui.ListMenu.new(game, "SAVE STATES", {
            { label = "STATE DATA ERROR", right = truncate(code, 6) },
          }, { onChoose = dispatch })
        end
        local items = {
          { label = "QUICK SAVES", right = tostring(summary.quickCount),
            onSelect = function()
              mod.ui.push(game, IDS.history, { class = "quick", parent = menu })
            end },
          { label = "AUTO SAVES", right = tostring(summary.autoCount),
            onSelect = function()
              mod.ui.push(game, IDS.history, { class = "auto", parent = menu })
            end },
          { label = "SAVE SLOTS",
            right = ("%d/%d"):format(summary.slotCount, summary.slotCapacity),
            onSelect = function()
              mod.ui.push(game, IDS.slots, { parent = menu })
            end },
        }
        if summary.undoAvailable then
          items[#items + 1] = { label = "UNDO LAST LOAD", onSelect = function()
            menu:close()
            service:undoLastLoad(game)
          end }
        end
        items[#items + 1] = { label = "SETTINGS", onSelect = function()
          mod.ui.push(game, IDS.settings, { parent = menu })
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
        local rows, code = service:listStates(game, class)
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
              right = row.available and Time.relative(row.metadata.createdAt, clock()) or "BAD",
              value = row,
              onSelect = function(item)
                mod.ui.push(game, IDS.actions, {
                  row = item.value,
                  parents = { menu, opts.parent },
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
        local row = opts.row or { metadata = {} }
        local metadata = row.metadata or {}
        local menu
        local items = {}
        if row.available then
          items[#items + 1] = { label = "LOAD", onSelect = function()
            closeMenus(menu, opts.parents)
            service:loadState(game, metadata.id)
          end }
          items[#items + 1] = { label = "PIN TO SLOT", onSelect = function()
            mod.ui.push(game, IDS.pinPicker, {
              sourceId = metadata.id,
              action = menu,
            })
          end }
        end
        items[#items + 1] = { label = "DELETE", onSelect = function()
          menu:close()
          local deleted = service:deleteState(game, metadata.id)
          local history = opts.parents and opts.parents[1]
          if deleted and history and history.removeCurrent then history:removeCurrent() end
        end }
        items[#items + 1] = { label = "CANCEL", onSelect = function()
          menu:close()
        end }
        menu = mod.ui.ListMenu.new(game, stateLabel(metadata), items, {
          onChoose = dispatch,
        })
        return menu
      end,
    })

    mod.content.screens:register(IDS.pinPicker, {
      new = function(game, opts)
        opts = opts or {}
        local rows = service:listSlots(game) or {}
        local menu
        local items = {}
        for slot = 1, 10 do
          local row = rows[slot] or { slot = slot, occupied = false }
          items[#items + 1] = {
            label = ("SLOT %d"):format(slot),
            right = row.occupied and truncate(row.metadata.label
              or row.metadata.locationName, 12) or "EMPTY",
            onSelect = function()
              local pinned = service:pinToSlot(game, opts.sourceId, slot)
              if pinned then
                menu:close()
                if opts.action and opts.action.close then opts.action:close() end
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
        local rows, code = service:listSlots(game)
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
        local slot = row.slot
        local menu
        local items = {}
        local function saveHere()
          closeMenus(menu, opts.parents)
          service:saveSlot(game, slot)
        end
        if not row.occupied then
          items[#items + 1] = { label = "SAVE HERE", onSelect = saveHere }
        else
          if row.available then
            items[#items + 1] = { label = "LOAD", onSelect = function()
              closeMenus(menu, opts.parents)
              service:loadSlot(game, slot)
            end }
          end
          items[#items + 1] = { label = "OVERWRITE", onSelect = saveHere }
          items[#items + 1] = { label = "RENAME", onSelect = function()
            mod.ui.push(game, IDS.rename, {
              slot = slot,
              action = menu,
              slotMenu = opts.slotMenu,
            })
          end }
          items[#items + 1] = { label = "DELETE", onSelect = function()
            menu:close()
            local deleted = service:deleteSlot(game, slot)
            if deleted and opts.slotMenu and opts.slotMenu.items[slot] then
              opts.slotMenu.items[slot].right = "EMPTY"
              opts.slotMenu.items[slot].value = { slot = slot, occupied = false }
            end
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
          maxLen = 10,
          onDone = function(name)
            if name == "" then return end
            local renamed = service:renameSlot(game, opts.slot, name)
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

    mod.content.screens:register(IDS.settings, {
      new = function(game)
        local function onOff(value) return value and "ON" or "OFF" end
        local items = {
          { label = "QUICK HISTORY", right = tostring(mod.options:get("quick_history")) },
          { label = "AUTO HISTORY", right = tostring(mod.options:get("auto_history")) },
          { label = "SAVE POPUPS", right = onOff(mod.options:get("save_notifications")) },
          { label = "LOAD POPUPS", right = onOff(mod.options:get("load_notifications")) },
        }
        return mod.ui.ListMenu.new(game, "STATE SETTINGS", items, {
          onChoose = function(_, menu) menu:close() end,
          footer = "CHANGE IN MODS > SAVE STATES",
        })
      end,
    })

    local out = {}
    for key, value in pairs(IDS) do out[key] = value end
    return out
  end

  return Registry
end
