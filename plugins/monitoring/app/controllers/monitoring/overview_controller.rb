module Monitoring
  class OverviewController < Monitoring::ApplicationController
    authorization_required

    def index
      all_alarms = services.monitoring.alarms()
      
      # first count alarms states, severity and alarms ins status ALARM
      # severity_cnt_hash = Hash.new(0)
      states_cnt_hash  = Hash.new(0)
      alarm_cnt_hash   = Hash.new(0)
      unknown_cnt_hash = Hash.new(0)

      # @severity_cnt = 0;
      # all_alarms.map{|alarm| alarm.severity }.map{|severity| 
      #   severity_cnt_hash[severity] += 1 
      #   @severity_cnt += 1
      # }
      
      @states_cnt = 0;
      all_alarms.map{|alarm| alarm.state }.map{|state| 
        states_cnt_hash[state] += 1
        @states_cnt += 1
      }
      
      @state_alarm_cnt = states_cnt_hash['ALARM']
      @state_unknown_cnt = states_cnt_hash['UNDETERMINED']
      all_alarms.map{|alarm|
        if alarm.state == 'ALARM'
          alarm_cnt_hash[alarm.severity] += 1
        elsif alarm.state == 'UNDETERMINED'
          unknown_cnt_hash[alarm.severity] += 1
        end
      }

      # then build pie data
      # @severity_pie_data    = Array.new
      @states_pie_data       = Array.new
      @state_alarm_pie_data = Array.new
      
      # severity data
      # @severity_pie_data = severity_cnt_hash.keys.sort.map{|severity| 
      #   { label: severity.capitalize, count: severity_cnt_hash[severity] }
      # }
      
      # all states data
      @states_pie_data = states_cnt_hash.keys.sort.map{|state| 
        # rename undetermined because it is to long for the chart label
        state_value = states_cnt_hash[state]
        state = "UNKNOWN" if state == 'UNDETERMINED'
        { label: state.capitalize, count: state_value } 
      }
      
      # only alarm state data
      @state_alarm_pie_data = alarm_cnt_hash.keys.sort.map{|state| 
        { label: state.capitalize, count: alarm_cnt_hash[state] }
      }

      # only unkown state data
      @state_unknown_pie_data = unknown_cnt_hash.keys.sort.map{|state| 
        { label: state.capitalize, count: unknown_cnt_hash[state] }
      }

    end

  end
end
