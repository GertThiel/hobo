module HoboRouteHelper
  extend HoboHelperBase
  protected
    def base_url
      ENV['RAILS_RELATIVE_URL_ROOT'] || ''
    end

    def controller_for(obj)
      if obj.is_a? Class
        obj.name.underscore.pluralize
      else
        obj.class.name.underscore.pluralize
      end
    end


    def subsite
      params[:controller]._?.match(/([^\/]+)\//)._?[1]
    end

    IMPLICIT_ACTIONS = [:index, :show, :create, :update, :destroy]

    def object_url(obj, *args)
      params = args.extract_options!
      action = args.first._?.to_sym
      options, params = params.partition_hash([:subsite, :method, :format])
      options[:subsite] ||= self.subsite
      subsite, method = options.get :subsite, :method

      if obj.respond_to?(:member_class) && obj.respond_to?(:origin) && obj.origin
        # Asking for URL of a collection, e.g. category/1/adverts or category/1/adverts/new

        refl = obj.origin.class.reverse_reflection(obj.origin_attribute)
        owner_name = refl.name.to_s
        owner_name = owner_name.singularize if refl.macro == :has_many
        if action == :new
          action_path = "#{obj.origin_attribute}/new"
          action = :"new_for_#{owner_name}"
        elsif action.nil?
          action_path = obj.origin_attribute
          if method.to_s == 'post'
            action = :"create_for_#{owner_name}"
          else
            action = :"index_for_#{owner_name}"
          end
        end
        klass = obj.member_class
        obj = obj.origin
      else
        action ||= case options[:method].to_s
                   when 'put';    :update
                   when 'post';   :create
                   when 'delete'; :destroy
                   else; obj.is_a?(Class) ? :index : :show
                   end

        if options[:method].to_s == 'post' && obj.try.new_record?
          # Asking for url to post new record to
          obj = obj.class
        end

        klass = if obj.is_a?(Class)
                  obj
                elsif obj.respond_to?(:member_class)
                  obj.member_class # We get here if we're passed a scoped class
                else
                  obj.class
                end
      end

      if Hobo::Routes.linkable?(klass, action, options)

        url = base_url_for(obj, subsite, action)
        url += "/#{action_path || action}" unless action.in?(IMPLICIT_ACTIONS)

        params = make_params(params)
        params.blank? ? url : "#{url}?#{params}"
      end
    end


    def linkable?(*args)
      options = args.extract_options!
      target = args.empty? || args.first.is_a?(Symbol) ? this : args.shift
      action = args.first
      return false if action.nil? && target.try.new_record?

      if target.respond_to?(:member_class) && (origin = target.try.origin)
        klass = origin.class
        action = if action == :new
                   "new_#{target.origin_attribute.to_s.singularize}"
                 elsif action.nil?
                   target.origin_attribute
                 end
      elsif target.is_a?(Class)
        klass = target
        action ||= :index
      else
        klass = target.class
        action ||= :show
      end

      Hobo::Routes.linkable?(klass, action, options.reverse_merge(:subsite => subsite))
    end

    def base_url_for(object, subsite, action)
      path = object.to_url_path or Hobo::Error.new("cannot create url for #{object.inspect} (#{object.class})")
      "#{base_url}#{'/' + subsite unless subsite.blank?}/#{path}"
    end


    def recognize_page_path
      # round tripping params through the router will remove
      # unnecessary params
      url = params[:page_path] || url_for(params)
      if ENV['RAILS_RELATIVE_URL_ROOT']
        url.gsub!(/^#{ENV['RAILS_RELATIVE_URL_ROOT']}/, "")
        url.gsub!(/^https?:\/\/.*?#{ENV['RAILS_RELATIVE_URL_ROOT']}/, "")
      end
      Rails.application.routes.recognize_path(url)
    end

    def url_for_page_path(options={})
      url_for recognize_page_path.merge(options)
    end

    def controller_action_from_page_path
      recognize_page_path.values_at(:controller,:action)
    end

    def defined_route?(r)
      @view.respond_to?("#{r}_url")
    end

    def _as_params(name, obj)
      if obj.is_a? Array
        obj.map {|x| _as_params("#{name}[]", x)}.join("&")
      elsif obj.is_a? Hash
        obj.map {|k,v| _as_params("#{name}[#{k}]", v)}.join("&")
      elsif obj.is_a? Hobo::RawJs
        "#{name}=' + #{obj} + '"
      else
        v = if obj.is_one_of?(ActiveRecord::Base, Array)
              "@" + typed_id(obj)
            else
              obj.to_s.gsub("'"){"\\'"}
            end
        "#{name}=#{v}"
      end
    end

    def make_params(*hashes)
      hash = {}
      hashes.each {|h| hash.update(h) if h}
      hash.map {|k,v| _as_params(k, v)}.join("&")
    end

    def current_page_url
      request.fullpath.match(/^([^?]*)/)._?[1]
    end

    # Login url for a given user record or user class
    def forgot_password_url(user_class=Hobo::Model::UserBase.default_user_model)
      send("#{user_class.name.underscore}_forgot_password_url") rescue nil
    end


    # Login url for a given user record or user class
    def login_url(user_class=Hobo::Model::UserBase.default_user_model)
      send("#{user_class.name.underscore}_login_url") rescue nil
    end


    # Sign-up url for a given user record or user class
    def signup_url(user_class=Hobo::Model::UserBase.default_user_model)
      send("#{user_class.name.underscore}_signup_url") rescue nil
    end


    # Login url for a given user record or user class
    def logout_url(user_or_class=nil)
      c = if user_or_class.nil?
            current_user.class
          elsif user_or_class.is_a?(Class)
            user_or_class
          else
            user_or_class.class
          end
      send("#{c.name.underscore}_logout_url") rescue nil
    end

    def new_for_current_user(model_or_assoc=nil)
      model_or_assoc ||= this
      if model_or_assoc.respond_to?(:new_candidate)
        model_or_assoc.user_new_candidate(current_user)
      else
        model_or_assoc.user_new(current_user)
      end
    end

end
