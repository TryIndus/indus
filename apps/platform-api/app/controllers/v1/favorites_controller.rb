module V1
  class FavoritesController < ApplicationController
    def index
      result = page(policy_scope(Favorite))
      render json: { items: result[:records].map { |favorite| favorite_json(favorite) }, next_cursor: result[:next_cursor] }
    end

    def create
      attributes = contract_params(:symbol, :instrument_type, required: %i[symbol instrument_type])
      favorite = Current.user.favorites.create!(attributes)
      authorize favorite
      response.set_header("Location", "/v1/favorites/#{favorite.symbol}")
      render json: favorite_json(favorite), status: :created
    end

    def destroy
      symbol = params[:symbol].to_s.upcase
      type = params[:instrument_type]
      scope = policy_scope(Favorite).where(symbol: symbol)
      scope = scope.where(instrument_type: type) if type.present?
      scope.find_each do |favorite|
        authorize favorite
        favorite.destroy!
      end
      head :no_content
    end
  end
end
