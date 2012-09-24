require 'moip_transparente'
module CatarseMoip::Payment
  class MoipController < ApplicationController
    layout :false

    def review
      @moip = ::MoipTransparente::Checkout.new
    end

    def moip_response
      @backer = current_user.backs.find params[:id]

      @backer.payment_notifications.create(extra_data: params[:response])

      unless @backer.confirmed and params[:response]['Status'] == 'Autorizado'
        @backer.confirm!
      end

      unless params[:response]['StatusPagamento'] == 'Falha'
        @backer.update_attributes({
          payment_id: params[:response]['CodigoMoIP'],
          payment_service_fee: params[:response]['TaxaMoIP'].to_f
        })
      end

      render nothing: true, status: 200
    end

    def get_moip_token
      @backer = current_user.backs.not_confirmed.find params[:id]

      ::MoipTransparente::Config.test = ::Configuration[:moip_test]
      ::MoipTransparente::Config.access_token = ::Configuration[:moip_token]
      ::MoipTransparente::Config.access_key = ::Configuration[:moip_key]

      @moip = ::MoipTransparente::Checkout.new

      invoice = {
        razao: "Apoio para o projeto '#{@backer.project.name}'",
        id: @backer.key,
        total: @backer.value.to_s,
        acrescimo: '0.00',
        desconto: '0.00',
        cliente: {
          id: @backer.user.id,
          nome: @backer.payer_name,
          email: @backer.payer_email,
          logradouro: "#{@backer.address_street}, #{@backer.address_number}",
          complemento: @backer.address_complement,
          bairro: @backer.address_neighbourhood,
          cidade: @backer.address_city,
          uf: @backer.address_state,
          cep: @backer.address_zip_code,
          telefone: @backer.address_phone_number
        }
      }

      response = @moip.get_token(invoice)

      session[:thank_you_id] = @backer.project.id

      if response and response[:token]
        @backer.update_column :payment_token, response[:token]
      end

      render json: { moip: @moip, widget_tag: @moip.widget_tag('checkoutSuccessful', 'checkoutFailure'), javascript_tag: @moip.javascript_tag }
    end

    def pay
      @backer = current_user.backs.not_confirmed.find params[:id]
      begin
        response = MoIP::Client.checkout(payment_info)
        @backer.update_attribute :payment_token, response["Token"]
        session[:_payment_token] = response["Token"]

        redirect_to MoIP::Client.moip_page(response["Token"])
      rescue Exception => e
        Airbrake.notify({ :error_class => "Checkout MOIP Error", :error_message => "MOIP Error: #{e.inspect}", :parameters => params}) rescue nil
        Rails.logger.info "-----> #{e.inspect}"
        flash[:failure] = t('projects.backers.checkout.moip_error')
        return redirect_to main_app.new_project_backer_path(@backer.project)
      end
    end

    protected

    def payer_info
      {
        nome: current_user.full_name,
        email: current_user.email,
        logradouro: current_user.address_street,
        numero: current_user.address_number,
        complemento: current_user.address_complement,
        bairro: current_user.address_neighbourhood,
        cidade: current_user.address_city,
        estado: current_user.address_state,
        pais: 'BRA',
        cep: current_user.address_zip_code,
        tel_fixo: current_user.phone_number
      }
    end

    def payment_info
      {
        valor: "%0.0f" % (@backer.value),
        id_proprio: @backer.key,
        razao: "Apoio para o projeto '#{@backer.project.name}'",
        forma: "BoletoBancario",
        dias_expiracao: 2,
        pagador: payer_info,
        url_retorno: main_app.thank_you_url
      }
    end
  end
end
