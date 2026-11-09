-- Subtle bloom: emissive things are drawn into a half-resolution buffer,
-- blurred with a separable gaussian, then added on top of the scene.
local Bloom = { enabled = true, intensity = 0.6 }

local SCALE = 0.5
local PASSES = 2
local canvasA, canvasB, shader

local BLUR = [[
extern vec2 dir;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 sum = Texel(tex, tc) * 0.2270270270;
  sum += Texel(tex, tc + dir * 1.3846153846) * 0.3162162162;
  sum += Texel(tex, tc - dir * 1.3846153846) * 0.3162162162;
  sum += Texel(tex, tc + dir * 3.2307692308) * 0.0702702703;
  sum += Texel(tex, tc - dir * 3.2307692308) * 0.0702702703;
  return sum * color;
}
]]

function Bloom.load(w, h)
  local format = require("core.platform").canvasFormat()
  canvasA = love.graphics.newCanvas(w * SCALE, h * SCALE, { format = format })
  canvasB = love.graphics.newCanvas(w * SCALE, h * SCALE, { format = format })
  shader = love.graphics.newShader(BLUR)
end

-- drawFn draws the glowing things in world coordinates; the result is added onto `target`
-- (a canvas, or nil for the screen).
function Bloom.draw(drawFn, target)
  if not Bloom.enabled then return end

  love.graphics.push("all")
  love.graphics.setCanvas(canvasA)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.origin()
  love.graphics.scale(SCALE)
  drawFn()
  love.graphics.pop()

  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setShader(shader)
  love.graphics.setBlendMode("alpha", "premultiplied")
  local tw, th = 1 / canvasA:getWidth(), 1 / canvasA:getHeight()
  for _ = 1, PASSES do
    love.graphics.setCanvas(canvasB)
    love.graphics.clear(0, 0, 0, 0)
    shader:send("dir", { tw, 0 })
    love.graphics.draw(canvasA)
    love.graphics.setCanvas(canvasA)
    love.graphics.clear(0, 0, 0, 0)
    shader:send("dir", { 0, th })
    love.graphics.draw(canvasB)
  end
  love.graphics.setCanvas(target)
  love.graphics.setShader()

  local k = Bloom.intensity
  love.graphics.setBlendMode("add", "premultiplied")
  love.graphics.setColor(k, k, k, k)
  love.graphics.draw(canvasA, 0, 0, 0, 1 / SCALE, 1 / SCALE)
  love.graphics.pop()
end

return Bloom
