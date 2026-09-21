module V1
  class MarketHistoryController < ApplicationController
    def show
      snapshot = MarketHistory::YahooAdapter.new.fetch(symbol: params[:symbol])
      render json: { symbol: snapshot.symbol, currency: snapshot.currency, range: "1y", points: snapshot.points }
    end
  end
end
