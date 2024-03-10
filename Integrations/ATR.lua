local addon = select(2, ...)

local ATR = {}
addon.ATR = ATR

function ATR.IsLoaded()
  if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemLink and Auctionator.API.v1.RegisterForDBUpdate then
    return true
  end
  return false
end

function ATR.GetItemValue(itemLink, priceSource)
  if not ATR.IsLoaded() then
    return 0
  end

  return Auctionator.API.v1.GetAuctionPriceByItemLink("AAATransformer", itemLink)
end

function ATR.GetAvailablePriceSources()
  if not ATR.IsLoaded() then
    return
  end

  local ps = {}
  local keys = { "ATRMarket" }
  for _, v in ipairs(keys) do
    ps[v] = addon.CONST.PRICE_SOURCE[v]
  end

  return ps
end
