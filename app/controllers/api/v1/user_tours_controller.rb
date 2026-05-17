class Api::V1::UserToursController < Api::BaseController
  def index
    tours = current_user.user_tours.order(:completed_at)
    success_response(
      data: tours.map { |t| serialize_tour(t) },
      message: 'Tours retrieved successfully'
    )
  end

  def create
    tour = current_user.user_tours.find_or_initialize_by(tour_key: tour_params[:tour_key])
    tour.completed_at = tour_params[:completed_at].presence || Time.current
    tour.status = tour_params[:status].presence.then { |s| UserTour::STATUSES.include?(s) ? s : 'completed' }

    if tour.save
      success_response(
        data: serialize_tour(tour),
        message: 'Tour saved successfully'
      )
    else
      render_unprocessable_entity(tour.errors)
    end
  end

  def destroy
    tour = current_user.user_tours.find_by(tour_key: params[:id])

    if tour
      tour.destroy
      success_response(data: {}, message: 'Tour reset successfully')
    else
      render_not_found('Tour not found')
    end
  end

  private

  def tour_params
    params.require(:tour).permit(:tour_key, :completed_at, :status)
  end

  def serialize_tour(tour)
    {
      id: tour.id,
      tour_key: tour.tour_key,
      completed_at: tour.completed_at,
      status: tour.status
    }
  end
end
