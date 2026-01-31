module Core
  class Admin::AnalyticsController < Admin::ApplicationController
    #skip_before_action :authorize_admins, only: [:index, :sinfo, :create_comment], raise: false
    before_action :require_analytics_access
    before_action :octo_authorize!
    octo_use(:project_class, :core, 'Project')

    before_action :prepare_comments, only: [:index, :create_comment]

    def index
      @total_reports     = 0
      @submitted_reports = 0
      @assessing_reports = 0
      @rejected_reports  = 0

      @systems = Core::Analytics::System.order(:name).includes(:nodes)

      node_states_rel = Core::Analytics::NodeState.current

      @global_state_counts = node_states_rel.group(:state).count

      @system_stats = {}
      @systems.each do |system|
        @system_stats[system.id] = {
          total_nodes: system.nodes.size,
          states:      Hash.new(0),
          issues:      0
        }
      end

      states_counts = node_states_rel.group(:system_id, :state).count
      states_counts.each do |(system_id, state), count|
        next unless @system_stats.key?(system_id)
        @system_stats[system_id][:states][state] = count
      end

      issues_counts = node_states_rel.where(has_reason: true).group(:system_id).count
      issues_counts.each do |system_id, count|
        next unless @system_stats.key?(system_id)
        @system_stats[system_id][:issues] = count
      end

      @partition_stats = {}

      partition_counts = node_states_rel.joins(:partition)
                                        .group(
                                          'core_analytics_partitions.system_id',
                                          'core_analytics_partitions.id',
                                          'core_analytics_partitions.name',
                                          'core_analytics_node_states.state'
                                        ).count

      partition_counts.each do |(system_id, partition_id, partition_name, state), count|
        @partition_stats[system_id] ||= {}
        @partition_stats[system_id][partition_id] ||= {
          name:   partition_name,
          states: Hash.new(0)
        }
        @partition_stats[system_id][partition_id][:states][state] = count
      end

      @latest_snapshots = Core::Analytics::Snapshot.latest_first.includes(:system).limit(10)
      @snapshot_stats   = {}

      if @latest_snapshots.any?
        snapshot_ids = @latest_snapshots.map(&:id)
        snapshot_counts = Core::Analytics::NodeState.where(snapshot_id: snapshot_ids)
                                                    .group(:snapshot_id, :state)
                                                    .count
        snapshot_counts.each do |(snap_id, state), count|
          @snapshot_stats[snap_id] ||= {}
          @snapshot_stats[snap_id][state] = count
        end
      end

      # @comment ||= Core::Comments::Comment.new
      # @recent_comments = Core::Comments::Comment.order(valid_from: :desc, created_at: :desc)
                                                

      @active_tab ||= 'analytics'
    end


    def sinfo
      fetcher = Core::SinfoFetcher.new(
        host: ENV.fetch("HPC_HOST", "188.44.52.12"),
        user: ENV.fetch("HPC_USER", "papchenko30_2363"),
        auth: { forward_agent: true }
      )
      @sinfo_log = fetcher.call.to_s

      result = ActiveRecord::Base.transaction do
        Core::SinfoIngestor.new(
          raw_text: @sinfo_log,
          source_cmd: 'sinfo -a',
          parser_version: 'v1',
          quiet: true
        ).call
      end

      respond_to do |format|
        format.js do
          js = <<~JS
            var panel = document.getElementById('sinfo_log_panel');
            var pre   = document.getElementById('sinfo_log');
            var res   = document.getElementById('sinfo_result');

            if (panel) { panel.style.display = 'block'; }
            if (pre)   { pre.textContent = #{(@sinfo_log.presence || "(пустой вывод)").to_json}; }
            if (res)   { res.textContent = #{result.to_json}; }
          JS
          render js: js
        end
        format.html do
          flash.now[:notice] = "SINFO загружен. Снимок ##{result[:snapshot_id]}, узлов: #{result[:nodes_total]}, строк: #{result[:rows_written]}, партиций: #{result[:partitions]}"
          index
          render :index
        end
        format.any { render json: { ok: true, result: result, sinfo: @sinfo_log }, status: 200 }
      end
    rescue => e
      Rails.logger.error("[analytics#sinfo] #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
      respond_to do |format|
        format.js   { render js: "alert('Ошибка загрузки SINFO: #{e.message}');", status: 500 }
        format.html { redirect_to action: :index, alert: "Ошибка: #{e.message}" }
        format.any  { render json: { ok: false, error: e.message }, status: 500 }
      end
    end

    def create_comment
      if request.get?
        index
        @active_tab = 'comments'
        render :index
        return
      end

      @comment = Core::Comments::Comment.new(comment_params)

      comments_user = Core::Comments::User.find_or_initialize_by(email: current_user.email)
      if comments_user.new_record?
        comments_user.name =
          current_user.try(:full_name) ||
          current_user.try(:name) ||
          current_user.email
        comments_user.save!
      end

      @comment.author = comments_user
      new_tag_ids = ensure_custom_tags(custom_tag_labels_from_params)
      @comment.tag_ids = (@comment.tag_ids + new_tag_ids).uniq if new_tag_ids.any?


      if @comment.save
        flash[:notice] = 'Комментарий сохранён.'
        redirect_to url_for(controller: '/core/admin/analytics', action: :create_comment)
      else
        flash.now[:alert] = 'Не удалось сохранить комментарий.'
        index
        @active_tab = 'comments'
        render :index
      end
    end

    def create_tag
      label = params.dig(:tag, :label).to_s.strip
      return render_tags_update(alert: 'Введите название тега.', status: 422) if label.blank?

      group = Core::Comments::TagGroup.find_or_create_by!(key: 'custom') do |g|
        g.name = 'Пользовательские'
        g.sort_order = 1000
        g.is_active = true
      end

      base_key = label.parameterize(separator: '_')
      base_key = "tag_#{SecureRandom.hex(4)}" if base_key.blank?

      key = base_key
      i = 2
      while Core::Comments::Tag.exists?(group_id: group.id, key: key)
        key = "#{base_key}_#{i}"
        i += 1
      end

      tag = Core::Comments::Tag.new(
        group_id: group.id,
        key: key,
        label: label,
        sort_order: 0,
        is_active: true
      )

      if tag.save
        render_tags_update(notice: 'Тег добавлен.', auto_check_tag_id: tag.id)
      else
        render_tags_update(alert: tag.errors.full_messages.to_sentence, status: 422)
      end
    end


    def destroy_tag
      tag = Core::Comments::Tag.find(params[:id])

      if tag.group&.key != 'custom'
        return render_tags_update(alert: 'Удалять можно только пользовательские теги (custom).', status: 422)
      end

      tag.destroy
      render_tags_update(notice: 'Тег удалён.')
    end



    private


    def comment_params
      key =
        if params[:comment].present?
          :comment
        elsif params[:comments_comment].present?
          :comments_comment
        else
          raise ActionController::ParameterMissing, :comment
        end

      permitted = params.require(key).permit(
        :system_id,
        :title,
        :body,
        :valid_from,
        :valid_to,
        :severity,
        node_ids: [],
        tag_ids: []
      )

      permitted[:node_ids] = Array(permitted[:node_ids]).reject(&:blank?).map(&:to_i).uniq
      permitted[:tag_ids]  = Array(permitted[:tag_ids]).reject(&:blank?).map(&:to_i).uniq

      permitted
    end



    def role?(name)
      return false unless current_user

      sym  = name.to_sym
      pred = "#{sym}?".to_sym
      if current_user.respond_to?(pred)
        current_user.public_send(pred)
      elsif current_user.respond_to?(:has_role?)
        current_user.has_role?(sym)
      else
        false
      end
    end

    def can_read_reports?
      return false unless respond_to?(:can?)
      begin
        can?(:read, :reports) || can?(:manage, :reports)
      rescue StandardError
        false
      end
    end

    def require_analytics_access
      allowed = role?(:superadmin) ||
                role?(:reregistrator) ||
                role?(:admin) ||
                role?(:expert) ||
                can_read_reports?

      redirect_to main_app.admin_users_path, alert: 'Нет доступа к аналитике' unless allowed
    end

    def prepare_comments

      @tag_groups = Core::Comments::TagGroup.includes(:tags).order(:sort_order, :id)
      @tag_usage  = Core::Comments::CommentTag.group(:tag_id).count

      @comment ||= Core::Comments::Comment.new(valid_from: Time.current)

      @nodes = Core::Analytics::Node
                .select(:id, :system_id, :hostname, :prefix)
                .order(:system_id, :prefix, :hostname)

      @tag_groups = Core::Comments::TagGroup.includes(:tags).order(:sort_order, :id)

      rel = Core::Comments::Comment
              .includes(:author, :system, :tags, :nodes)
              .recent_first

      rel = rel.where(system_id: params[:system_id]) if params[:system_id].present?
      rel = rel.where(severity: params[:severity]) if params[:severity].present?
      rel = rel.current if params[:active_only].to_s == '1'

      @recent_comments = rel.limit(20)
    end


    def custom_tag_labels_from_params
      raw = params.dig(:comment, :new_tags) || params.dig(:comments_comment, :new_tags)
      return [] if raw.blank?

      raw.to_s
        .split(/[,\n;]/)
        .map { |s| s.strip }
        .reject(&:blank?)
        .uniq
        .take(10)
    end

    def ensure_custom_tags(labels)
      return [] if labels.blank?

      group = Core::Comments::TagGroup.find_or_create_by!(key: 'custom') do |g|
        g.name = 'Пользовательские'
        g.sort_order = 1000
        g.is_active = true
      end

      labels.map { |label| find_or_create_tag_in_group(group, label).id }
    end

    def find_or_create_tag_in_group(group, label)
      # сначала пытаемся найти по label (без учёта регистра)
      existing = Core::Comments::Tag.where(group_id: group.id)
                                  .where('LOWER(label) = ?', label.downcase)
                                  .first
      return existing if existing

      base_key = label.to_s.parameterize(separator: '_')
      base_key = "tag_#{SecureRandom.hex(4)}" if base_key.blank?

      key = base_key
      i = 2
      while Core::Comments::Tag.exists?(group_id: group.id, key: key)
        key = "#{base_key}_#{i}"
        i += 1
      end

      Core::Comments::Tag.create!(
        group_id: group.id,
        key: key,
        label: label,
        sort_order: 0,
        is_active: true
      )
    end

    def load_tags_data
      @tag_groups = Core::Comments::TagGroup.includes(:tags).order(:sort_order, :id)
      @tag_usage  = Core::Comments::CommentTag.group(:tag_id).count
    end

    def render_tags_update(notice: nil, alert: nil, auto_check_tag_id: nil, status: 200)
      load_tags_data

      checkboxes_html = render_to_string(
        partial: 'core/admin/analytics/tags_checkboxes',
        formats: [:html],
        locals: { tag_groups: @tag_groups, comment: @comment || Core::Comments::Comment.new }
      )

      manage_html = render_to_string(
        partial: 'core/admin/analytics/tags_manage',
        formats: [:html],
        locals: { tag_groups: @tag_groups, tag_usage: @tag_usage }
      )

      js = <<~JS
        (function(){
          // запомним отмеченные теги в форме комментария
          var checked = Array.prototype.slice.call(
            document.querySelectorAll('#tag_checkboxes_container input[type="checkbox"]:checked')
          ).map(function(cb){ return cb.value; });

          var c = document.getElementById('tag_checkboxes_container');
          var m = document.getElementById('tag_manage_container');

          if (c) { c.innerHTML = #{checkboxes_html.to_json}; }
          if (m) { m.innerHTML = #{manage_html.to_json}; }

          // восстановим отмеченные теги
          checked.forEach(function(id){
            var cb = document.querySelector('#tag_checkboxes_container input[type="checkbox"][value="'+id+'"]');
            if (cb) cb.checked = true;
          });

          // авто-отметим новый тег (если нужно)
          #{auto_check_tag_id ? "var cb2=document.querySelector('#tag_checkboxes_container input[type=\"checkbox\"][value=\"#{auto_check_tag_id}\"]'); if(cb2) cb2.checked=true;" : ""}

          var n=document.getElementById('tags_notice');
          if(n){
            n.textContent = #{(notice || '').to_json};
            n.style.display = #{notice ? "'block'" : "'none'"};
          }
          var a=document.getElementById('tags_alert');
          if(a){
            a.textContent = #{(alert || '').to_json};
            a.style.display = #{alert ? "'block'" : "'none'"};
          }
        })();
      JS

      render js: js, status: status
    end

  end
end
