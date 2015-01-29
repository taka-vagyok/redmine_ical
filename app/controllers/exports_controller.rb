# -*- coding: utf-8 -*-
require "icalendar"
require "icalendar/tzinfo"
class ExportsController < ApplicationController
  unloadable
  skip_before_filter :check_if_login_required
  SALT_CHARSET = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

  def show
    ical_setting = IcalSetting.where(:token => params[:id]).first
    if ical_setting
      user = User.find(ical_setting.user_id)
      send_data generate_ical(ical_setting, user), :type => 'text/calendar; charset=utf-8'
      #render :text => generate_ical(ical_setting, user)
    else
      render :text => "403", :status => :forbidden
    end
  end

  def set_uid(id)
    salt = "" << SALT_CHARSET[rand 64] << SALT_CHARSET[rand 64]
    "#{id.to_s.crypt(salt)}@example.com"
  end

  def get_unclosed_my_issues(user)
    #Today = Date.today
    #startdt = today - ical_setting.past
    #enddt = today + ical_setting.future

    #watchers = []
    #watch_users = []
    #Watcher.find(:all,
    #  :joins => "LEFT JOIN users ON watchers.user_id = users.id", :conditions => ["watchers.user_id = ? AND watchers.watchable_type = ?", user.id, "Issue"]).each do  |watcher|
    #  watchers << watcher.watchable_id
    #  watch_users << watcher.user
    #end
    #issues = Issue.find(:all, :conditions => ["start_date >= ? AND due_date <= ? AND (assigned_to_id = ? OR id IN (?) )", startdt, enddt, user.id, watchers.uniq])

    # 未完了で自分の担当のチケットを取得
    #issues = Issue.find(:all, :joins => "LEFT JOIN issue_statuses AS st ON issues.status_id = st.id", :conditions => ["issues.start_date <= ? AND issues.due_date <= ? AND issues.assigned_to_id = ? AND st.is_closed = ?", startdt, enddt, user.id, false])
    issues = Issue.find(:all, :joins => "LEFT JOIN issue_statuses AS st ON issues.status_id = st.id", :conditions => ["issues.assigned_to_id = ? AND st.is_closed = ?", user.id, false])

    # Add watching issues, too
    #issues += Issue.find(:all, :joins => "LEFT JOIN issue_statuses AS st ON issues.status_id = st.id", :conditions => ["? IN (issues.watcher_user_ids) AND st.is_closed = ?", user.id,  false])
    return issues
  end

  def generate_ical(ical_setting, user)
    # get issues
    issues = get_unclosed_my_issues(user)
    # gen calendar
    cal = Icalendar::Calendar.new
    # タイムゾーン (VTIMEZONE) を作成
    cal.timezone do |t|
      t.tzid = 'Asia/Tokyo'
      t.standard do |tst|
        tst.tzoffsetfrom = '+0900'
        tst.tzoffsetto   = '+0900'
        # should set but not worked gem icalendar 2.2.1 bug?. comment out 12/27
        #tst.tzname       = 'JST'
        tst.dtstart      = '19700101T000000'
      end
    end

    ical_name = "Redmine Issue Calender(#{user.name})"
    cal.append_custom_property("X-WR-CALNAME", ical_name)
    cal.append_custom_property("X-WR-CALDESC", ical_name)
    cal.append_custom_property("X-WR-TIMEZONE","Asia/Tokyo")
    cal.prodid = "Redmine iCal Plugin"
    issues.each do |issue|
      next if issue.start_date.blank?
      next if issue.due_date.blank?
      s  = issue.start_date
      e  = issue.due_date

      event = Icalendar::Event.new
      event.summary = issue.subject

      # 終日だとhour,minは不要
      # 終日だと開始日の次の日
      event.dtstart = Icalendar::Values::Date.new( s.strftime("%Y%m%d") )
      event.dtend = Icalendar::Values::Date.new( (e + 1.day ).strftime("%Y%m%d") )
      event.append_custom_property("CONTACT;CN=#{user.name}", "MAILTO:#{user.mail}")
      event.description = issue.description
      event.url = "#{request.protocol}#{request.host_with_port}/issues/#{issue.id}"
      event.created = issue.created_on.strftime("%Y%m%dT%H%M%SZ")
      event.last_modified = issue.updated_on.strftime("%Y%m%dT%H%M%SZ")
      #event.uid("#{issue.id}@example.com") #Defines a persistent, globally unique id for this item
      event.uid = set_uid(issue.id) #Defines a persistent, globally unique id for this item
      # event.klass("PRIVATE")
      # 作成者が参加者の中にいればAtendeeではなくorganizerにする
      # watch_users.each do |watcher|
      #   if issue.assigned_to_id
      #     if watcher.id == issue.assigned_to_id
      #       event.custom_property("ORGANIZER;CN=#{watcher.name}", "MAILTO:#{watcher.mail}")
      #       event.custom_property("ATTENDEE;ROLE=CHAIR;CN=#{watcher.name}", "MAILTO:#{watcher.mail}")
      #     else
      #       attendee = Attendee.new(watcher.mail, {"CN" => watcher.name})
      #       event.custom_property attendee.property_name, attendee.value
      #     end
      #   else
      #     if watcher.id == issue.author_id
      #       event.custom_property("ORGANIZER;CN=#{watcher.name}", "MAILTO:#{watcher.mail}")
      #       event.custom_property("ATTENDEE;ROLE=CHAIR;CN=#{watcher.name}", "MAILTO:#{watcher.mail}")
      #     else
      #       attendee = Attendee.new(watcher.mail, {"CN" => watcher.name})
      #       event.custom_property attendee.property_name, attendee.value
      #     end
      #   end
      # end

      event.append_custom_property("ORGANIZER;CN=#{user.name}", "MAILTO:#{user.mail}")
      event.append_custom_property("ATTENDEE;ROLE=CHAIR;CN=#{user.name}", "MAILTO:#{user.mail}")
      watcher_join = "LEFT JOIN users ON watchers.user_id = users.id"
      watcher_condition =  ["watchers.watchable_type = ? AND watchers.watchable_id = ?", "Issue", issue.id]
      Watcher.find(:all,:joins => watcher_join ,:conditions => watcher_condition ).each do |watcher|
        watched_user = watcher.user
        attendee = Attendee.new(watched_user.mail, {"CN" => watched_user.name})
        event.append_custom_property attendee.property_name, attendee.value
      end

      # 設定値を見る
      if ical_setting
        if ical_setting.alerm
          # アラーム (VALARM) を作成 (複数作成可能)
          event.alarm do |alm|
            alm.action     = "DISPLAY"  # 表示で知らせる
            alm.trigger    = "-PT#{ical_setting.time_number}#{ical_setting.time_section}"    # -PT5M=5分前に, -PT3H=3時間前, -P1D=1日前
          end
        #else
        #  event.alarm.action = "NONE"
        end
      end
      cal.add_event event
    end
    # iCalのContent-Typeが必要
    #self.headers['Content-Type'] = "text/calendar; charset=UTF-8"
    cal.publish
    cal.to_ical
  end

  class Attendee
    attr :mailto, true
    attr :params, true

    def initialize(mailto, params={})
      self.mailto = mailto
      self.params = params
    end

    def property_name
      param_str = ""
      params.each do |key, value|
        param_str << ";" if param_str.empty?
        param_str << "#{key}=#{value}"
      end
      "ATTENDEE#{param_str}"
    end

    def value
      "MAILTO:#{mailto}"
    end
  end

  class Organizer
    attr :mailto, true
    attr :params, true

    def initialize(mailto, params={})
      self.mailto = mailto
      self.params = params
    end

    def property_name
      param_str = ""
      params.each do |key, value|
        param_str << ";" if param_str.empty?
        param_str << "#{key}=#{value}"
      end
      "ATTENDEE#{param_str}"
    end

    def value
      "MAILTO:#{mailto}"
    end
  end



end

