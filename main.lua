-- Save States: public-API composition root.
--
-- The technical shell intentionally has no gameplay effect. Product modules are
-- loaded through mod:read + load as they land; distributable code never imports
-- private engine modules.
return function(mod)
  mod.log:info("Save States %s loaded (technical preview)", mod.version)
end
