local titanServer = require(script.Parent.OdysseyEngine.Services.TitanService)

while task.wait(1) do
	if not workspace.Titans.Alive:FindFirstChildWhichIsA("Model") then
		titanServer.new(Vector3.new(50, 50, 50), "Mindless")
	end
end