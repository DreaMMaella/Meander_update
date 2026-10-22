-- Панель статуса (эталон плагина L3B).
--
-- Фокус, который стоит показать: числа в шкалах — это НЕ значения, а
-- привязки `{hp}` / `{hpMax}`. Рендерер подставляет текущие переменные
-- квеста при каждой перерисовке, поэтому нарисованный один раз HUD живёт
-- сам; Lua нужен только там, где появляется новая логика (отдых, бодрость,
-- которая копится сама при переходе между сценами).

local DETAILS = 'details'

--- Значение переменной как число: Lua получает данные из JSON, где переменная
--  вполне может быть строкой или отсутствовать.
local function num(value, fallback)
  if type(value) == 'number' then return value end
  if type(value) == 'string' then return tonumber(value) or fallback end
  return fallback
end

local function append(list, items)
  for _, item in ipairs(items) do
    list[#list + 1] = item
  end
  return list
end

local function bar(caption, value, max, color, icon)
  return {
    type = 'column',
    gap = 3,
    align = 'stretch',
    children = {
      {
        type = 'row',
        children = {
          { type = 'icon', icon = icon, color = color, size = 16 },
          { type = 'text', text = caption .. '  ' .. value .. ' / ' .. max, color = 'white', size = 13 },
        },
      },
      {
        type = 'progress',
        value = value,
        max = max,
        color = color,
        background = '#26262F',
        height = 8,
      },
    },
  }
end

local function bars()
  local result = { bar('Здоровье', '{hp}', '{hpMax}', 'red', 'heart') }
  if mnd.vars.has('energy') then
    result[#result + 1] = { type = 'spacer', size = 6 }
    result[#result + 1] = bar('Бодрость', '{energy}', '{energyMax}', 'cyan', 'drop')
  end
  return result
end

local function hudSpec()
  local children = append({
    { type = 'badge', label = 'Состояние', background = '#26262F', color = 'gray', radius = 8 },
    { type = 'spacer', size = 8 },
  }, bars())
  append(children, {
    { type = 'spacer', size = 10 },
    {
      type = 'button',
      label = 'Отдохнуть',
      icon = 'bulb',
      variant = 'outline',
      color = 'white',
      border = '#3A3A46',
      onPress = 'rest',
    },
    { type = 'spacer', size = 4 },
    {
      type = 'button',
      label = 'Персонаж',
      icon = 'person',
      variant = 'text',
      color = 'gold',
      onPress = 'openDetails',
    },
  })
  return {
    type = 'card',
    align = 'stretch',
    background = '#1B1B22',
    border = '#3A3A46',
    radius = 16,
    padding = 12,
    children = children,
  }
end

local function detailsSpec()
  local children = {
    {
      type = 'row',
      children = {
        { type = 'heading', text = '{characterName}', color = 'white', expand = true },
        { type = 'badge', label = 'ур. {level}', background = 'gold', color = 'black' },
      },
    },
    { type = 'divider', color = '#3A3A46' },
  }
  append(children, bars())
  if mnd.vars.has('inv') then
    append(children, {
      { type = 'divider', color = '#3A3A46' },
      { type = 'caption', text = 'Сумка', color = 'gray' },
      {
        type = 'list',
        items = '{inv}',
        gap = 4,
        row = {
          type = 'row',
          children = {
            { type = 'icon', icon = 'bag', size = 16, color = 'gray' },
            { type = 'text', text = '{name}', color = 'white', expand = true },
            { type = 'text', text = '× {count}', color = 'gray' },
          },
        },
      },
    })
  end
  append(children, {
    { type = 'spacer', size = 12 },
    {
      type = 'button',
      label = 'Отдохнуть',
      icon = 'bulb',
      color = 'black',
      background = 'gold',
      onPress = 'rest',
    },
    {
      type = 'button',
      label = 'Закрыть',
      variant = 'outline',
      color = 'white',
      border = '#3A3A46',
      onPress = 'closeDetails',
    },
  })
  return {
    type = 'card',
    align = 'stretch',
    background = '#15151B',
    border = '#3A3A46',
    radius = 20,
    padding = 18,
    children = children,
  }
end

--- Квест не обязан вести счёт здоровья — плагин заводит его сам, иначе
--  демонстрационная панель в чистом квесте была бы пустой.
local function ensureVitals()
  if not mnd.vars.has('hp') then
    mnd.vars.set('hpMax', 100)
    mnd.vars.set('hp', 100)
    mnd.log.info('statushud: переменных hp/hpMax не было — создаю 100/100')
  end
  if not mnd.vars.has('energy') then
    mnd.vars.set('energyMax', 6)
    mnd.vars.set('energy', 6)
  end
  if not mnd.vars.has('characterName') then mnd.vars.set('characterName', 'Странник') end
  if not mnd.vars.has('level') then mnd.vars.set('level', 1) end
end

local function renderHud()
  mnd.ui.render('slot:status', hudSpec())
end

function on_quest_start()
  ensureVitals()
  renderHud()
end

function on_node_enter()
  ensureVitals()
  -- Шаг между сценами сам по себе возвращает силы: бодрость копится на
  -- новой ноде, поэтому «Отдохнуть» остаётся осмысленной тратой,
  -- а не бесплатным лечением.
  local energy = num(mnd.vars.get('energy'), 0)
  local energyMax = num(mnd.vars.get('energyMax'), 6)
  if energy < energyMax then mnd.vars.set('energy', energy + 1) end
  mnd.ui.close('slot:' .. DETAILS)
  renderHud()
end

function on_item_press()
  renderHud()
end

function openDetails()
  mnd.ui.render('slot:' .. DETAILS, detailsSpec())
end

function closeDetails()
  mnd.ui.close('slot:' .. DETAILS)
end

function rest()
  local hp = num(mnd.vars.get('hp'), 0)
  local hpMax = num(mnd.vars.get('hpMax'), 100)
  local energy = num(mnd.vars.get('energy'), 0)
  if hp >= hpMax then
    mnd.ui.toast('Отдыхать не от чего', 1600)
    return
  end
  if energy < 1 then
    mnd.ui.toast('Слишком устали, чтобы отдыхать', 1600)
    return
  end
  local healed = math.min(hpMax - hp, 25)
  mnd.vars.set('energy', energy - 1)
  mnd.vars.set('hp', hp + healed)
  mnd.ui.toast('Отдых: +' .. healed .. ' здоровья, −1 бодрости', 1800)
  renderHud()
end
