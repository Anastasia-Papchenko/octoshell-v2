module Core
  module Comments
    class Comment < ApplicationRecord
      self.table_name = 'core_comments'

      belongs_to :author,
           class_name: 'Core::Comments::User',
           foreign_key: :author_id

      enum :severity, {
        info: 0,    
        warning: 1,  
        incident: 2  
      }, prefix: :severity

      TAG_GROUPS = {
        'incident' => {
          name: 'Нештатные ситуации',
          tags: [
            { key: 'outside_temp_high',             label: 'Аномально высокая уличная температура' },
            { key: 'cooling_partial_outage',        label: 'Отключение/недоступность части системы охлаждения' },
            { key: 'power_limitation',              label: 'Ограничение энергоснабжения' },
            { key: 'generic_incident',              label: 'Аварийная ситуация (общее)' },
            { key: 'interconnect_perf_degradation', label: 'Снижение производительности сети межсоединений' },
            { key: 'node_mass_failure',             label: 'Массовый отказ части вычислительных узлов' },
            { key: 'login_nodes_unavailable',       label: 'Недоступность/проблемы с узлами логина' },
            { key: 'scheduler_issues',              label: 'Недоступность/нестабильность системы очередей' },
            { key: 'filesystem_io_problems',        label: 'Проблемы с файловой системой (задержки / ошибки I/O)' }
          ]
        },
        'mode_change' => {
          name: 'Изменение режима работы СКЦ',
          tags: [
            { key: 'big_jobs_dedicated_mode',          label: 'Режим выделенных расчётов для больших задач' },
            { key: 'priority_projects_dedicated_mode', label: 'Режим выделенных расчётов для приоритетных проектов' },
            { key: 'new_hw_commissioning',             label: 'Введение в эксплуатацию нового оборудования' },
            { key: 'reduced_user_limits',              label: 'Временное снижение пользовательских лимитов' },
            { key: 'benchmark_mode',                   label: 'Режим бенчмарков / тестирования производительности' },
            { key: 'training_mode',                    label: 'Учебный режим (курсы, мастер-классы)' },
            { key: 'sysconfig_testing',                label: 'Тестирование новых настроек системного ПО' }
          ]
        },
        'maintenance' => {
          name: 'Профилактические и ремонтные работы',
          tags: [
            { key: 'system_software_update',   label: 'Обновление системного ПО' },
            { key: 'filesystem_config_change', label: 'Изменения в настройках файловой системы' },
            { key: 'scratch_cleanup',          label: 'Очистка scratch' },
            { key: 'support_systems_update',   label: 'Обновление системы поддержки функционирования СКЦ' },
            { key: 'storage_maintenance',      label: 'Профилактика/ремонт дисковой подсистемы' },
            { key: 'network_maintenance',      label: 'Работы с сетевой инфраструктурой' },
            { key: 'power_maintenance',        label: 'Работы с энергоснабжением / UPS' },
            { key: 'cooling_maintenance',      label: 'Работы с системой охлаждения' },
            { key: 'node_hw_replacement',      label: 'Замена/расширение вычислительных узлов' },
            { key: 'datacenter_works',         label: 'Плановые работы в машинном зале' }
          ]
        }
      }.freeze

      validates :title,      presence: true
      validates :valid_from, presence: true

      validate :valid_to_not_before_valid_from

      scope :recent_first, -> { order(valid_from: :desc, created_at: :desc) }
      scope :current, ->(moment = Time.current) {
        where('valid_from <= ? AND (valid_to IS NULL OR valid_to >= ?)', moment, moment)
      }

      def tag_keys=(value)
        keys = Array(value).reject(&:blank?).map(&:to_s).uniq
        super(keys)
      end

      def tags
        all_tags_index.values_at(*tag_keys).compact
      end

      def self.tag_groups
        TAG_GROUPS
      end

      def self.all_tags_index
        @all_tags_index ||= TAG_GROUPS.values
                                     .flat_map { |g| g[:tags] }
                                     .index_by { |t| t[:key] }
      end

      private

      def all_tags_index
        self.class.all_tags_index
      end

      def valid_to_not_before_valid_from
        return if valid_to.blank? || valid_from.blank?
        errors.add(:valid_to, 'не может быть раньше даты начала действия') if valid_to < valid_from
      end
    end
  end
end
