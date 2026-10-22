-- Кодовый замок (эталон плагина L3B).
--
-- Самый показательный пример: целая игровая механика, которой в движке нет.
-- Плагин объявляет собственный тип контента, рисует клавиатуру прямо в
-- айтеме сцены и сам решает, что делать с введённым кодом. Никакого
-- нативного кода: только события EventContract, команды UI и переменные.
--
-- Ввод хранится в переменной квеста `lock_<айтем>` — значит условие видимости
-- двери может проверять его без всякого плагина, а прогресс попадания
-- переживает сохранение.

local DEFAULT_CODE = '1337'
local DEFAULT_ATTEMPTS = 3
local MAX_ATTEMPTS = 9

--- Имя переменной/ключа должно быть ASCII-идентификатором: id айтема — uuid.
local function slug(value)
  return (string.gsub(tostring(value), '[^%w_]', '_'))
end

local function progressVar(itemId)
  return 'lock_' .. slug(itemId)
end

--- Сколько попыток осталось. Отдельная переменная — счётчик обязан
--  переживать сохранение квеста, как и сам ввод.
local function leftVar(itemId)
  return 'lockleft_' .. slug(itemId)
end

--- Настройки замка per-quest: хранилище плагина одно на все квесты.
local function configKey(itemId)
  return 'cfg:' .. mnd.questId .. ':' .. itemId
end

local function endsWith(text, suffix)
  return #text >= #suffix and string.sub(text, -#suffix) == suffix
end

local function isOurItem(item)
  if type(item) ~= 'table' or item.type ~= 'plugin' then return false end
  if item.pluginId == mnd.pluginId then return true end
  return type(item.pluginTypeId) == 'string' and endsWith(item.pluginTypeId, 'combinationLock')
end

local function trimmed(value)
  if type(value) ~= 'string' then return '' end
  return value:match('^%s*(.-)%s*$')
end

--- `pluginData` приходит из формы редактора: всё может оказаться пустым,
--  число — прийти строкой, а `bool` — словом.
local function configOf(item)
  local data = type(item.pluginData) == 'table' and item.pluginData or {}
  local code = trimmed(data.code)
  if code == '' then code = DEFAULT_CODE end
  local title = trimmed(data.title)
  local attempts = tonumber(data.attempts)
  if attempts == nil then attempts = DEFAULT_ATTEMPTS end
  attempts = math.floor(attempts)
  if attempts < 1 then attempts = 1 end
  if attempts > MAX_ATTEMPTS then attempts = MAX_ATTEMPTS end
  return {
    code = code,
    title = title ~= '' and title or 'Замок',
    hint = trimmed(data.hint),
    target = trimmed(data.targetNode),
    picture = trimmed(data.picture),
    attempts = attempts,
    -- «сложный» — набираемые цифры не показываются, только точки;
    -- «с клавиатуры» — вместо экранной клавиатуры обычное поле ввода.
    blind = trimmed(data.mode) == 'сложный',
    keypad = trimmed(data.mode) ~= 'с клавиатуры',
    showProgress = data.showProgress ~= false and data.showProgress ~= 'false',
  }
end

--- Счётчик живёт в переменной квеста, поэтому его видно в отладке прогресса.
--  Пустое или вышедшее за рамки значение — «полный запас попыток».
local function attemptsLeft(itemId, cfg)
  local stored = math.floor(tonumber(mnd.vars.get(leftVar(itemId))) or cfg.attempts)
  if stored < 0 or stored > cfg.attempts then return cfg.attempts end
  return stored
end

local function notice(cfg, itemId)
  return 'Осталось попыток: ' .. attemptsLeft(itemId, cfg)
end

local function entered(itemId)
  return tostring(mnd.vars.get(progressVar(itemId)) or '')
end

--- Ряд кнопок: `args` несёт и айтем, и цифру — один плагин обслуживает
--  сколько угодно замков на сцене.
local function key(itemId, label, variant)
  return {
    type = 'button',
    label = label,
    args = itemId .. '|' .. label,
    onPress = 'press',
    variant = variant,
    color = 'white',
    background = '#2E2E3A',
    border = '#454554',
  }
end

local function keyRow(itemId, first, second, third)
  return {
    type = 'row',
    justify = 'space',
    gap = 6,
    children = {
      key(itemId, first, 'filled'),
      key(itemId, second, 'filled'),
      key(itemId, third, 'filled'),
    },
  }
end

local function dots(cfg, value)
  local marks = {}
  for position = 1, #cfg.code do
    if position > #value then
      marks[position] = '○'
    elseif cfg.blind then
      marks[position] = '●'
    else
      marks[position] = string.sub(value, position, position)
    end
  end
  return table.concat(marks, '  ')
end

local function lockSpec(itemId, cfg)
  local value = entered(itemId)
  local children = {
    {
      type = 'row',
      children = {
        { type = 'icon', icon = 'lock', color = 'gold', size = 18 },
        { type = 'text', text = cfg.title, color = 'white', bold = true },
      },
    },
    { type = 'text', text = dots(cfg, value), color = 'gold', size = 20 },
  }
  if cfg.keypad then
    children[#children + 1] = keyRow(itemId, '1', '2', '3')
    children[#children + 1] = keyRow(itemId, '4', '5', '6')
    children[#children + 1] = keyRow(itemId, '7', '8', '9')
    children[#children + 1] = {
      type = 'row',
      justify = 'space',
      gap = 6,
      children = {
        key(itemId, 'C', 'outline'),
        key(itemId, '0', 'filled'),
        key(itemId, '<', 'outline'),
      },
    }
  else
    -- Поле с обычной клавиатуры: `value` привязан к той же переменной ввода,
    -- поэтому замок показывает набранное и после перерисовки карточки.
    children[#children + 1] = {
      type = 'input',
      placeholder = cfg.title .. ' — код',
      value = '{' .. progressVar(itemId) .. '}',
      password = cfg.blind,
      maxLength = #cfg.code,
      args = itemId,
      onChange = 'typing',
      onSubmit = 'submit',
    }
    children[#children + 1] = {
      type = 'button',
      label = 'Открыть',
      args = itemId,
      onPress = 'submit_tap',
      color = 'white',
      background = '#2E2E3A',
      border = '#454554',
    }
  end
  if cfg.picture ~= '' then
    table.insert(children, 1, {
      type = 'image',
      src = cfg.picture,
      height = 120,
      fit = 'contain',
      radius = 12,
    })
  end
  if cfg.hint ~= '' then
    table.insert(children, 3, { type = 'caption', text = cfg.hint, color = 'gray' })
  end
  if cfg.showProgress then
    table.insert(children, { type = 'caption', text = notice(cfg, itemId), color = 'gray' })
  end
  return {
    type = 'card',
    align = 'stretch',
    gap = 8,
    background = '#1B1B22',
    border = '#3A3A46',
    radius = 16,
    padding = 14,
    children = children,
  }
end

--- Состояние «открыто»: код совпал, и это видно даже если у квеста нет
--  отдельной сцены за дверью.
local function openSpec(itemId, cfg)
  return {
    type = 'card',
    align = 'stretch',
    gap = 6,
    background = '#16221A',
    border = '#2F5B3B',
    radius = 16,
    padding = 14,
    children = {
      {
        type = 'row',
        children = {
          { type = 'icon', icon = 'check', color = 'green', size = 20 },
          { type = 'text', text = cfg.title .. ' открыт', color = 'white', bold = true },
        },
      },
      {
        type = 'button',
        label = 'Закрыть обратно',
        args = itemId,
        onPress = 'relatch',
        variant = 'text',
        color = 'gray',
      },
    },
  }
end

local function render(itemId, spec)
  mnd.ui.render('item:' .. itemId, spec)
end

local function configOfStored(itemId)
  local cfg = mnd.storage.get(configKey(itemId))
  if type(cfg) ~= 'table' or type(cfg.code) ~= 'string' then return end
  -- Конфиг мог лежать в хранилище из прошлой версии плагина — новые поля
  -- нормализуем здесь, а не на каждый прочитанный cfg.
  cfg.picture = type(cfg.picture) == 'string' and cfg.picture or ''
  cfg.hint = type(cfg.hint) == 'string' and cfg.hint or ''
  cfg.blind = cfg.blind == true
  cfg.keypad = cfg.keypad ~= false
  cfg.showProgress = cfg.showProgress ~= false
  cfg.attempts = math.floor(tonumber(cfg.attempts) or DEFAULT_ATTEMPTS)
  if cfg.attempts < 1 then cfg.attempts = 1 end
  if cfg.attempts > MAX_ATTEMPTS then cfg.attempts = MAX_ATTEMPTS end
  return cfg
end

--- Ключевая ветка: код совпал. Пишем флаг в переменную квеста, показываем
--  открытое состояние и, если автор задал ноду, уводим игрока туда.
local function succeed(itemId, cfg)
  mnd.vars.set(progressVar(itemId), '')
  mnd.vars.set(leftVar(itemId), cfg.attempts)
  mnd.vars.set('unlocked_' .. slug(itemId), true)
  mnd.ui.toast(cfg.title .. ': код принят', 1600)
  render(itemId, openSpec(itemId, cfg))
  if cfg.target ~= nil and cfg.target ~= '' then
    mnd.game.go(cfg.target)
  end
end

--- Код набран целиком и не подошёл — это попытка. Когда они кончаются, замок
--  «заклинивает»: ввод стирается, а счётчик возвращается к полному запасу.
local function missAttempt(itemId, cfg)
  local left = attemptsLeft(itemId, cfg) - 1
  if left <= 0 then
    mnd.vars.set(leftVar(itemId), cfg.attempts)
    mnd.ui.toast(cfg.title .. ': заклинило, код сброшен', 1800)
  else
    mnd.vars.set(leftVar(itemId), left)
    mnd.ui.toast('Не тот код, попыток осталось: ' .. left, 1400)
  end
  mnd.vars.set(progressVar(itemId), '')
  render(itemId, lockSpec(itemId, cfg))
end

--- Общая проверка набранного кода: сюда сходятся и экранная клавиатура, и
--  обычная.
local function check(itemId, cfg, text)
  mnd.vars.set(progressVar(itemId), text)
  if text == cfg.code then
    succeed(itemId, cfg)
  else
    missAttempt(itemId, cfg)
  end
end

--- Ввод с обычной клавиатуры. `onChange` лишь зеркалит текст в переменную и
--  не перерисовывает карточку: перерисовка на каждом символе стоила бы фокуса.
function typing(argument)
  if type(argument) ~= 'table' then return end
  local itemId = argument.args
  if type(itemId) ~= 'string' or itemId == '' then return end
  mnd.vars.set(progressVar(itemId), tostring(argument.value or ''))
end

--- Enter в поле ввода: значение приходит аргументом колбэка.
function submit(argument)
  if type(argument) ~= 'table' then return end
  local itemId = argument.args
  if type(itemId) ~= 'string' then return end
  local cfg = configOfStored(itemId)
  if cfg == nil then
    mnd.log.warn('замок ' .. itemId .. ' не настроен — нет данных после item_reveal')
    return
  end
  local text = trimmed(argument.value)
  check(itemId, cfg, text ~= '' and text or entered(itemId))
end

--- Тап по кнопке «Открыть»: текст берём из переменной, куда его положил
--  `onChange` поля.
function submit_tap(argument)
  local itemId = type(argument) == 'string' and argument or ''
  local cfg = configOfStored(itemId)
  if cfg == nil then return end
  check(itemId, cfg, entered(itemId))
end

function press(argument)
  if type(argument) ~= 'string' then return end
  local itemId, digit = argument:match('^(.-)|(.+)$')
  if itemId == nil then return end
  local cfg = configOfStored(itemId)
  if cfg == nil then
    mnd.log.warn('замок ' .. itemId .. ' не настроен — нет данных после item_reveal')
    return
  end
  local value = entered(itemId)
  if digit == 'C' then
    value = ''
  elseif digit == '<' then
    value = string.sub(value, 1, math.max(0, #value - 1))
  else
    if #value >= #cfg.code then value = '' end
    value = value .. digit
  end
  if #value ~= #cfg.code then
    mnd.vars.set(progressVar(itemId), value)
    render(itemId, lockSpec(itemId, cfg))
    return
  end
  check(itemId, cfg, value)
end

--- Возврат замка в закрытое состояние — полезно, если игрок открыл дверь
--  и хочет посмотреть, как это работало, или если квест не увёл его со сцены.
function relatch(argument)
  local itemId = type(argument) == 'string' and argument or ''
  local cfg = configOfStored(itemId)
  if cfg == nil then return end
  mnd.vars.set('unlocked_' .. slug(itemId), false)
  mnd.vars.set(progressVar(itemId), '')
  mnd.vars.set(leftVar(itemId), cfg.attempts)
  render(itemId, lockSpec(itemId, cfg))
end

function on_item_reveal(payload)
  if type(payload) ~= 'table' then return end
  local item = payload.item_json
  if not isOurItem(item) then return end
  local itemId = item.id or payload.item_id or ''
  if itemId == '' then return end
  local cfg = configOf(item)
  mnd.storage.set(configKey(itemId), cfg)
  render(itemId, lockSpec(itemId, cfg))
end

--- Тап по самому айтему: возвращаем клавиатуру, если её сняли при переходе
--  на ноду (surface'ы айтемов живут ровно одну сцену).
function on_item_press(payload)
  if type(payload) ~= 'table' then return end
  local itemId = payload.item_id or ''
  local cfg = configOfStored(itemId)
  if cfg == nil then return end
  render(itemId, lockSpec(itemId, cfg))
end
