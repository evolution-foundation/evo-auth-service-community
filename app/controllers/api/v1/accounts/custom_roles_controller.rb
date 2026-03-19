module Api
  module V1
    module Accounts
      class CustomRolesController < Api::V1::Accounts::BaseController
        before_action :set_custom_role, only: [:show, :update, :destroy, :add_permission,
                                              :remove_permission, :update_permissions,
                                              :add_resource_scope, :remove_resource_scope,
                                              :resource_scopes, :update_resource_scopes]

        # GET /api/v1/accounts/:account_id/custom_roles
        def index
          @custom_roles = Current.account
                                  .account_custom_roles
                                  .includes(:created_by, :updated_by)
                                  .ordered

          # Filtros opcionais
          @custom_roles = @custom_roles.active if params[:active] == 'true'
          @custom_roles = @custom_roles.inactive if params[:active] == 'false'

          apply_pagination
          
          paginated_response(
            data: @custom_roles.map { |role| AccountCustomRoleSerializer.full(role) },
            collection: @custom_roles,
            message: 'Custom roles retrieved successfully'
          )
        end

        # GET /api/v1/accounts/:account_id/custom_roles/:id
        def show
          success_response(
            data: {
            custom_role: AccountCustomRoleSerializer.full(@custom_role),
            permissions: @custom_role.permission_keys,
            permissions_by_resource: @custom_role.permissions_by_resource,
            resource_scopes: @custom_role.resource_scopes
            },
            message: 'Custom role retrieved successfully'
          )
        end

        # POST /api/v1/accounts/:account_id/custom_roles
        def create
          @custom_role = Current.account.account_custom_roles.build(custom_role_params)
          @custom_role.created_by = Current.user

          if @custom_role.save
            # Adicionar permissões se fornecidas
            if params[:permissions].present?
              @custom_role.add_permissions(params[:permissions])
            end

            # Adicionar resource scopes se fornecidos
            if params[:resource_scopes].present?
              add_resource_scopes_from_params(params[:resource_scopes])
            end

            success_response(
              data: { custom_role: AccountCustomRoleSerializer.full(@custom_role.reload) },
              message: 'Custom role created successfully',
              status: :created
            )
          else
            error_response('OPERATION_FAILED', @custom_role.errors.full_messages.join(', '), details: @custom_role.errors.full_messages, status: :unprocessable_entity)
          end
        end

        # PATCH/PUT /api/v1/accounts/:account_id/custom_roles/:id
        def update
          @custom_role.updated_by = Current.user

          if @custom_role.update(custom_role_params)
            # Atualizar permissões se fornecidas
            if params[:permissions].present?
              @custom_role.update_permissions(params[:permissions])
            end

            # Atualizar resource scopes se fornecidos
            if params[:resource_scopes].present?
              ActiveRecord::Base.transaction do
                @custom_role.account_custom_role_resource_scopes.destroy_all
                add_resource_scopes_from_params(params[:resource_scopes])
              end
            end

            success_response(
              data: { custom_role: AccountCustomRoleSerializer.full(@custom_role.reload) },
              message: 'Custom role updated successfully'
            )
          else
            error_response('OPERATION_FAILED', @custom_role.errors.full_messages.join(', '), details: @custom_role.errors.full_messages, status: :unprocessable_entity)
          end
        end

        # DELETE /api/v1/accounts/:account_id/custom_roles/:id
        def destroy
          if @custom_role.account_users.exists?
            error_response(
              message: 'Cannot delete custom role with assigned users',
              status: :unprocessable_entity
            )
            return
          end

          if @custom_role.destroy
            success_response(
              data: {},
              message: 'Custom role deleted successfully'
            )
          else
            error_response('OPERATION_FAILED', @custom_role.errors.full_messages.join(', '), details: @custom_role.errors.full_messages, status: :unprocessable_entity)
          end
        end

        # POST /api/v1/accounts/:account_id/custom_roles/:id/add_permission
        def add_permission
          permission_key = params[:permission_key]

          if permission_key.blank?
            error_response('VALIDATION_ERROR', 'Permission key is required', status: :bad_request)
            return
          end

          if @custom_role.add_permission(permission_key)
            success_response(
              data: { permissions: @custom_role.permission_keys },
              message: 'Permission added successfully'
            )
          else
            error_response(
              message: 'Failed to add permission. Invalid permission key.',
              status: :unprocessable_entity
            )
          end
        end

        # DELETE /api/v1/accounts/:account_id/custom_roles/:id/remove_permission
        def remove_permission
          permission_key = params[:permission_key]

          if permission_key.blank?
            error_response('VALIDATION_ERROR', 'Permission key is required', status: :bad_request)
            return
          end

          count = @custom_role.remove_permission(permission_key)
          success_response(
            data: { permissions: @custom_role.permission_keys },
            message: "#{count} permission(s) removed"
          )
        end

        # PUT /api/v1/accounts/:account_id/custom_roles/:id/update_permissions
        def update_permissions
          permission_keys = params[:permissions] || []

          count = @custom_role.update_permissions(permission_keys)
          success_response(
            data: {
              permissions: @custom_role.permission_keys,
              permissions_by_resource: @custom_role.permissions_by_resource
            },
            message: "Permissions updated. #{count} valid permissions set."
          )
        end

        # POST /api/v1/accounts/:account_id/custom_roles/:id/add_resource_scope
        def add_resource_scope
          resource_type = params[:resource_type]
          resource_id = params[:resource_id]
          actions = params[:actions] || ['read']

          if resource_type.blank? || resource_id.blank?
            error_response(
              message: 'Resource type and resource ID are required',
              status: :bad_request
            )
            return
          end

          begin
            scope = @custom_role.add_resource_scope(resource_type, resource_id, actions)
            success_response(
              data: {
                resource_scope: scope,
                resource_scopes: @custom_role.resource_scopes
              },
              message: 'Resource scope added successfully',
              status: :created
            )
          rescue ActiveRecord::RecordInvalid => e
            error_response(
              message: e.message,
              status: :unprocessable_entity
            )
          end
        end

        # DELETE /api/v1/accounts/:account_id/custom_roles/:id/remove_resource_scope
        def remove_resource_scope
          resource_type = params[:resource_type]
          resource_id = params[:resource_id]

          if resource_type.blank? || resource_id.blank?
            error_response(
              message: 'Resource type and resource ID are required',
              status: :bad_request
            )
            return
          end

          count = @custom_role.remove_resource_scope(resource_type, resource_id)
          success_response(
            data: { resource_scopes: @custom_role.resource_scopes },
            message: "#{count} resource scope(s) removed"
          )
        end

        # GET /api/v1/accounts/:account_id/custom_roles/:id/resource_scopes
        def resource_scopes
          success_response(
            data: {
            resource_scopes: @custom_role.resource_scopes,
            scopes_by_type: @custom_role.account_custom_role_resource_scopes
                                        .group_by(&:resource_type)
            },
            message: 'Resource scopes retrieved successfully'
          )
        end

        # PUT /api/v1/accounts/:account_id/custom_roles/:id/update_resource_scopes
        def update_resource_scopes
          scopes_data = params[:resource_scopes] || []

          ActiveRecord::Base.transaction do
            # Remover todos os scopes existentes
            @custom_role.account_custom_role_resource_scopes.destroy_all

            # Adicionar novos scopes
            scopes_data.each do |scope_data|
              @custom_role.add_resource_scope(
                scope_data[:resource_type],
                scope_data[:resource_id],
                scope_data[:actions] || ['read']
              )
            end
          end

          success_response(
            data: { resource_scopes: @custom_role.reload.resource_scopes },
            message: 'Resource scopes updated successfully'
          )
        rescue ActiveRecord::RecordInvalid => e
          error_response(
            message: e.message,
            status: :unprocessable_entity
          )
        end

        # GET /api/v1/accounts/:account_id/custom_roles/available_permissions
        def available_permissions
          success_response(
            data: {
            available_permissions: ResourceActionsConfig.all_permission_keys,
            resources: ResourceActionsConfig.all_resources.transform_values do |resource|
              {
                name: resource[:name],
                description: resource[:description],
                actions: resource[:actions].keys.map(&:to_s)
              }
            end
            },
            message: 'Available permissions retrieved successfully'
          )
        end

        private

        def set_custom_role
          @custom_role = Current.account.account_custom_roles.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          error_response('NOT_FOUND', 'Custom role not found', status: :not_found)
        end

        def custom_role_params
          params.require(:custom_role).permit(:key, :name, :description, :is_active)
        end

        def add_resource_scopes_from_params(scopes_data)
          Array(scopes_data).each do |scope_data|
            @custom_role.add_resource_scope(
              scope_data[:resource_type],
              scope_data[:resource_id],
              scope_data[:actions] || ['read']
            )
          rescue ActiveRecord::RecordInvalid => e
            Rails.logger.warn "Failed to add resource scope: #{e.message}"
            next
          end
        end
      end
    end
  end
end
