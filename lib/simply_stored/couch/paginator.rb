require 'will_paginate/collection'
module SimplyStored
  module Couch
    module Paginator
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def build_pagination(options = {})
          params = {}
          params[:per_page] = options[:per_page] || 10
          params[:page] = options[:page] || 1
          self.page_params = params
          self
        end

        def build_pagination_params
          hash = {}
          hash[:skip] = ((page_params[:page].to_i) -1) * page_params[:per_page].to_i if page_params[:page] and page_params[:per_page]
          hash[:limit] = page_params[:per_page] if page_params[:per_page]
          hash
        end

      end
    end

    module Helper
      def self.paginate results, options
        per_page = options[:limit]
        page = 1
        total = results.total_rows
        WillPaginate::Collection.create(page, per_page, total) do |pager|
          pager.replace results[pager.offset, pager.per_page].to_a
        end
      end

      def self.eager_load(results, params)
        results.compact!
        return if results.empty?

        params.each do |param|
          param_id = "#{param}_id".to_sym

          raise ArgumentError, "No such relation: #{param}" unless results.first.respond_to?(param)
          if results.first.respond_to?(param_id)
            param_ids = results.map(&param_id)
            objs = CouchPotato.database.load param_ids.compact
            grouped_objs = objs.group_by(&:id)

            results.each do |result|
              result.send("#{param}=", grouped_objs[result.send(param_id)].try(:first) ) if result.send(param_id)
            end
          else
            to = results.first.class
            from_class = to.association_classes[param].constantize
            from =  from_class.to_s.underscore
            foreign_key_id = (to.foreign_keys && to.foreign_keys[param]) || to.foreign_key
            foreign_key = foreign_key_id.gsub(/_id$/, '')
            view_options = {:include_docs=>true, :reduce=>false, :keys => results.map(&:id)}
            objs = CouchPotato.database.view(from_class.send("eager_load_association_#{from}_belongs_to_#{foreign_key}", view_options) )
            grouped_objs = objs.group_by(&foreign_key_id.to_sym)

            results.each do |result|
              result.instance_eval do
                cache_key = _cache_key_for(nil)
                eager_loaded_results = grouped_objs[result.id]
                send("_set_cached_#{param}", (eager_loaded_results || []), cache_key)
                #result.class.set_parent_has_many_association_object(result, eager_loaded_results)
              end
            end
          end
        end
        results

      end
    end

  end
end



