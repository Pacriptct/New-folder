-- ReplicatedStorage.Packages.CharacterCreator
--
-- Public API for the shared character-creator runtime. Both modules
-- are also reachable directly as `Packages.CharacterCreator.RigUtils`
-- and `Packages.CharacterCreator.Config` — the table form below is
-- there for callers that prefer a single require.

return {
	RigUtils = require(script.RigUtils),
	Config   = require(script.Config),
}
