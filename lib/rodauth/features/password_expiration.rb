module Rodauth
  PasswordExpiration = Feature.define(:password_expiration) do
    depends :login, :change_password

    notice_flash "Your password has expired and needs to be changed"
    notice_flash "Your password cannot be changed yet", 'password_not_changeable_yet'

    redirect :password_not_changeable_yet 
    redirect(:password_change_needed){"#{prefix}/#{change_password_route}"}

    auth_value_method :allow_password_change_after, 0
    auth_value_method :require_password_change_after, 90*86400
    auth_value_method :password_expiration_table, :account_password_change_times
    auth_value_method :password_expiration_id_column, :id
    auth_value_method :password_expiration_changed_at_column, :changed_at
    auth_value_method :password_expiration_session_key, :password_expired

    auth_methods(
      :password_expired?,
      :update_password_changed_at
    )

    def before_change_password
      check_password_change_allowed
      super
    end

    def check_password_change_allowed
      if password_changed_at = password_expiration_ds.get(password_expiration_changed_at_column)
        if password_changed_at > Time.now - allow_password_change_after
          set_notice_flash password_not_changeable_yet_notice_flash
          request.redirect password_not_changeable_yet_redirect
        end
      end
    end

    def set_password(password)
      update_password_changed_at
      session.delete(password_expiration_session_key)
      super
    end

    def after_create_account
      if account_password_hash_column
        update_password_changed_at
      end
      super
    end

    def password_expiration_ds
      db[password_expiration_table].where(password_expiration_id_column=>account_id_value)
    end

    def _account_from_reset_password_key(key)
      a = super
      check_password_change_allowed
      a
    end

    def update_password_changed_at
      ds = password_expiration_ds
      if ds.update(password_expiration_changed_at_column=>Sequel::CURRENT_TIMESTAMP) == 0
        ds.insert(password_expiration_id_column=>account_id_value)
      end
    end

    def after_login
      super
      require_current_password
    end

    def require_current_password
      return unless logged_in?
      _account_from_session
      if password_expired?
        set_notice_flash password_expiration_notice_flash
        request.redirect password_change_needed_redirect
      end
    end

    def password_expired?
      if session.has_key?(password_expiration_session_key)
        return session[password_expiration_session_key]
      end

      session[password_expiration_session_key] = if password_changed_at = password_expiration_ds.get(password_expiration_changed_at_column) || false
        password_changed_at = Time.parse(password_changed_at) if password_changed_at.is_a?(String)
        password_changed_at < Time.now - require_password_change_after
      end
    end
  end
end