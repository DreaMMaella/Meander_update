-- Лавка (эталон плагина L3B).
--
-- Здесь плагин делает то, чего в квесте как жанре вообще не было: берёт экран
-- целиком (`screen`), заводит собственную экономику в переменных квеста и
-- помнит остаток на складе между сессиями в своём хранилище. Движок при этом
-- не знает слова «лавка» — он умеет только рисовать спек и применять записи
-- переменных.
--
-- Вторая хитрость — шапка с монетами: `label = '{gold}'` подставляется при
-- каждой перерисовке, поэтому счёт денег живёт без единого лишнего `render`.

local MAX_STOCK = 5

--- Товары витрины. Данные, а не код: цена, иконка из конечного списка и подсказка.
local CATALOG = {
  { key = 'torch', name = 'Факел', price = 12, icon = 'fire', note = 'Тепло и свет в подвале' },
  { key = 'keyring', name = 'Связка ключей', price = 25, icon = 'key', note = 'Открывает половину дверей' },
  { key = 'bandage', name = 'Бинт', price = 8, icon = 'cross', note = 'Перевязать рану на ходу' },
  { key = 'lantern', name = 'Лампа', price = 40, icon = 'bulb', note = 'Долго горит, тяжело стоит' },
}

local function num(value, fallback)
  if type(value) == 'number' then return value end
  if type(value) == 'string' then return tonumber(value) or fallback end
  return fallback
end

local function stockKey()
  -- Хранилище плагина одно на всё приложение, а не на квест: без префикса
  -- склад из одного квеста закончился бы в другом.
  return 'stock:' .. mnd.questId
end

local function fullStock()
  local stock = {}
  for _, item in ipairs(CATALOG) do
    stock[item.key] = MAX_STOCK
  end
  return stock
end

local function stockTable()
  local stock = mnd.storage.get(stockKey())
  if type(stock) ~= 'table' then
    stock = fullStock()
    mnd.storage.set(stockKey(), stock)
  end
  return stock
end

--- Ключ переменной монет: квест может вести счёт под своим именем.
local function gold()
  if not mnd.vars.has('gold') then
    mnd.vars.set('gold', 40)
    mnd.log.info('shop: переменной gold не было — выдаю 40 на пробу')
  end
  return num(mnd.vars.get('gold'), 0)
end

local function itemOf(key)
  for _, item in ipairs(CATALOG) do
    if item.key == key then return item end
  end
  return nil
end

local function stockOf(stock, key)
  return num(stock[key], 0)
end

--- Покупка падает в сумку: список `{name, count}` в переменной `inv` — его же
--  рисует статус-панель, так что два плагина согласуются через данные квеста.
local function addToInventory(name)
  local inv = mnd.vars.get('inv')
  if type(inv) ~= 'table' then inv = {} end
  for _, entry in ipairs(inv) do
    if type(entry) == 'table' and entry.name == name then
      entry.count = num(entry.count, 0) + 1
      mnd.vars.set('inv', inv)
      return
    end
  end
  inv[#inv + 1] = { name = name, count = 1 }
  mnd.vars.set('inv', inv)
end

local function chipSpec()
  return {
    type = 'row',
    gap = 8,
    children = {
      {
        type = 'chip',
        label = 'Лавка · {gold}',
        icon = 'coin',
        background = '#1B1B22',
        color = 'gold',
        onPress = 'openShop',
      },
    },
  }
end

local function goodsRows(stock)
  local rows = {}
  for _, item in ipairs(CATALOG) do
    local left = stockOf(stock, item.key)
    local affordable = left > 0
    rows[#rows + 1] = {
      type = 'row',
      gap = 10,
      align = 'center',
      children = {
        { type = 'icon', icon = item.icon, size = 26, color = affordable and 'gold' or 'gray' },
        {
          type = 'column',
          expand = true,
          children = {
            { type = 'text', text = item.name, color = 'white', weight = 'bold' },
            { type = 'caption', text = item.note .. ' · ' .. item.price .. ' монет', color = 'gray' },
          },
        },
        {
          type = 'badge',
          label = left > 0 and ('остаток ' .. left) or 'нет',
          background = left > 0 and '#26262F' or 'red',
          color = left > 0 and 'gray' or 'white',
        },
        {
          type = 'button',
          label = 'Купить',
          args = item.key,
          onPress = 'buy',
          variant = affordable and 'filled' or 'outline',
        },
      },
    }
    rows[#rows + 1] = { type = 'divider', color = '#26262F' }
  end
  return rows
end

local function shopSpec()
  local children = {
    {
      type = 'row',
      children = {
        { type = 'heading', text = 'Лавка', color = 'white', expand = true },
        { type = 'badge', label = '{gold} монет', background = 'gold', color = 'black' },
      },
    },
    { type = 'caption', text = 'Товар не пропадает: сколько лежало, столько и купите.', color = 'gray' },
    { type = 'spacer', size = 6 },
  }
  for _, row in ipairs(goodsRows(stockTable())) do
    children[#children + 1] = row
  end
  children[#children + 1] = {
    type = 'button',
    label = 'Уйти',
    variant = 'outline',
    color = 'white',
    border = '#3A3A46',
    onPress = 'closeShop',
  }
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

local function renderChip()
  mnd.ui.render('slot:chip', chipSpec())
end

function on_quest_start()
  gold()
  stockTable()
  renderChip()
end

function on_node_enter()
  gold()
  renderChip()
end

function openShop()
  mnd.ui.render('screen', shopSpec())
end

function closeShop()
  mnd.ui.close('screen')
end

--- Аргумент кнопки — имя товара: `args` не подставляется переменными, поэтому
--  он буквально то, что положено в спек.
function buy(argument)
  local key = tostring(argument or '')
  local item = itemOf(key)
  if item == nil then
    mnd.log.warn('shop: незнакомый товар ' .. key)
    return
  end
  local money = gold()
  local stock = stockTable()
  local left = stockOf(stock, key)
  if left <= 0 then
    mnd.ui.toast('«' .. item.name .. '» закончился', 1800)
    return
  end
  if money < item.price then
    mnd.ui.toast('Не хватает ' .. (item.price - money) .. ' монет', 1800)
    return
  end
  mnd.vars.set('gold', money - item.price)
  stock[key] = left - 1
  mnd.storage.set(stockKey(), stock)
  addToInventory(item.name)
  mnd.audio.play('coins', 0.9)
  mnd.ui.toast(item.name .. ' — у вас. −' .. item.price .. ' монет', 1800)
  -- Остаток на витрине изменился, поэтому экран перерисовывается целиком.
  mnd.ui.render('screen', shopSpec())
end
