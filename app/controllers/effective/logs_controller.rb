module Effective
  class LogsController < ApplicationController
    skip_log_page_views quiet: true

    if respond_to?(:before_action) # Devise
      before_action :authenticate_user!, only: [:index, :show]
    else
      before_filter :authenticate_user!, only: [:index, :show]
    end

    # This is a post from our Javascript
    def create
      EffectiveLogging.authorized?(self, :create, Effective::Log.new())

      @log = Effective::Log.new().tap do |log|
        log.message = log_params[:message]
        log.status = (EffectiveLogging.statuses.include?(log_params[:status]) ? log_params[:status] : 'info')
        log.user = (current_user rescue nil)

        count = -1
        Array((JSON.parse(log_params[:details]) rescue [])).flatten(1).each do |obj|
          if obj.kind_of?(Hash)
            obj.each { |k, v| log.details[k] = v if v.present? }
          else
            log.details["param_#{(count += 1)}"] = obj if obj.present?
          end
        end

        # Match the referrer
        log.details[:ip] ||= request.ip
        log.details[:referrer] ||= request.referrer
        log.details[:user_agent] ||= request.user_agent

        log.save
      end

      render text: 'ok', status: :ok, json: {}
    end

    # This is the User index event
    def index
      if Gem::Version.new(EffectiveDatatables::VERSION) < Gem::Version.new('3.0')
        @datatable = Effective::Datatables::Logs.new(user_id: current_user.id)
      else
        @datatable = EffectiveLogsDatatable.new(self, user_id: current_user.id)
      end

      EffectiveLogging.authorized?(self, :index, Effective::Log.new(user_id: current_user.id))
    end

    # This is the User show event
    def show
      @log = Effective::Log.includes(:logs).find(params[:id])
      @log.next_log = Effective::Log.unscoped.order(:id).where(parent_id: @log.parent_id).where('id > ?', @log.id).first
      @log.prev_log = Effective::Log.unscoped.order(:id).where(parent_id: @log.parent_id).where('id < ?', @log.id).last

      @page_title = "Log ##{@log.to_param}"

      if @log.logs.present?
        if Gem::Version.new(EffectiveDatatables::VERSION) < Gem::Version.new('3.0')
          @log.datatable = Effective::Datatables::Logs.new(log_id: @log.id)
        else
          @log.datatable = EffectiveLogsDatatable.new(self, log_id: @log.id)
        end
      end

      EffectiveLogging.authorized?(self, :show, @log)
    end

    def html_part
      @log = Effective::Log.find(params[:id])

      EffectiveLogging.authorized?(self, :show, @log)

      value = @log.details[(params[:key] || '').to_sym].to_s

      open = value.index('<!DOCTYPE html') || value.index('<html')
      close = value.rindex('</html>') if open.present?

      if open.present? && close.present?
        render inline: value[open...(close+7)].html_safe
      else
        render inline: value.html_safe
      end
    end

    private

    # StrongParameters
    def log_params
      begin
        params.require(:effective_log).permit(:message, :status, :details)
      rescue => e
        params[:effective_log] || {}
      end
    end

  end
end
