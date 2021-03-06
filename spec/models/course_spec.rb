#
# Copyright (C) 2011 Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

require File.expand_path(File.dirname(__FILE__) + '/../spec_helper.rb')
require 'socket'

describe Course do
  before(:each) do
    @course = Course.new
  end
  
  context "validation" do
    it "should create a new instance given valid attributes" do
      course_model
    end
  end
  
  it "should create a unique course." do
    @course = Course.create_unique
    @course.name.should eql("My Course")
    @uuid = @course.uuid
    @course2 = Course.create_unique(@uuid)
    @course.should eql(@course2)
  end
  
  it "should always have a uuid, if it was created" do
    @course.save!
    @course.uuid.should_not be_nil
  end

  it "should follow account chain when looking for generic permissions from AccountUsers" do
    account = Account.create!
    sub_account = Account.create!(:parent_account => account)
    sub_sub_account = Account.create!(:parent_account => sub_account)
    user = account_admin_user(:account => sub_account)
    course = Course.create!(:account => sub_sub_account)
    course.grants_right?(user, nil, :manage).should be_true
  end
end

describe Course, "account" do
  before(:each) do
    @account = mock_model(Account)
    @account2 = mock_model(Account)
    @course = Course.new
  end
  
  it "should refer to the course's account" do
    @course.account = @account
    @course.account.should eql(@account)
  end
  
  it "should be sortable" do
    3.times {|x| Course.create(:name => x.to_s)}
    lambda{Course.find(:all).sort}.should_not raise_error
  end
end

describe Course, "enroll" do
  
  before(:each) do
    @course = Course.create(:name => "some_name")
    @user = user_with_pseudonym
  end
  
  it "should be able to enroll a student" do
    @course.enroll_student(@user)
    @se = @course.student_enrollments.first
    @se.user_id.should eql(@user.id)
    @se.course_id.should eql(@course.id)
  end
  
  it "should be able to enroll a TA" do
    @course.enroll_ta(@user)
    @tae = @course.ta_enrollments.first
    @tae.user_id.should eql(@user.id)
    @tae.course_id.should eql(@course.id)
  end
  
  it "should be able to enroll a teacher" do
    @course.enroll_teacher(@user)
    @te = @course.teacher_enrollments.first
    @te.user_id.should eql(@user.id)
    @te.course_id.should eql(@course.id)
  end
  
  it "should enroll a student as creation_pending if the course isn't published" do
    @se = @course.enroll_student(@user)
    @se.user_id.should eql(@user.id)
    @se.course_id.should eql(@course.id)
    @se.should be_creation_pending
  end
  
  it "should enroll a teacher as invited if the course isn't published" do
    Notification.create(:name => "Enrollment Registration", :category => "registration")
    @tae = @course.enroll_ta(@user)
    @tae.user_id.should eql(@user.id)
    @tae.course_id.should eql(@course.id)
    @tae.should be_invited
    @tae.messages_sent.should be_include("Enrollment Registration")
  end
  
  it "should enroll a ta as invited if the course isn't published" do
    Notification.create(:name => "Enrollment Registration", :category => "registration")
    @te = @course.enroll_teacher(@user)
    @te.user_id.should eql(@user.id)
    @te.course_id.should eql(@course.id)
    @te.should be_invited
    @te.messages_sent.should be_include("Enrollment Registration")
  end
end

describe Course, "score_to_grade" do
  it "should correctly map scores to grades" do
    default = GradingStandard.default_grading_standard
    default.to_json.should eql([["A", 1], ["A-", 0.93], ["B+", 0.89], ["B", 0.86], ["B-", 0.83], ["C+", 0.79], ["C", 0.76], ["C-", 0.73], ["D+", 0.69], ["D", 0.66], ["D-", 0.63], ["F", 0.6]].to_json)
    course_model
    @course.score_to_grade(95).should eql("")
    @course.grading_standard_id = 0
    @course.score_to_grade(1005).should eql("A")
    @course.score_to_grade(105).should eql("A")
    @course.score_to_grade(100).should eql("A")
    @course.score_to_grade(99).should eql("A")
    @course.score_to_grade(94).should eql("A")
    @course.score_to_grade(93.001).should eql("A")
    @course.score_to_grade(93).should eql("A-")
    @course.score_to_grade(92.999).should eql("A-")
    @course.score_to_grade(90).should eql("A-")
    @course.score_to_grade(89).should eql("B+")
    @course.score_to_grade(87).should eql("B+")
    @course.score_to_grade(86).should eql("B")
    @course.score_to_grade(85).should eql("B")
    @course.score_to_grade(83).should eql("B-")
    @course.score_to_grade(80).should eql("B-")
    @course.score_to_grade(79).should eql("C+")
    @course.score_to_grade(76).should eql("C")
    @course.score_to_grade(73).should eql("C-")
    @course.score_to_grade(71).should eql("C-")
    @course.score_to_grade(69).should eql("D+")
    @course.score_to_grade(67).should eql("D+")
    @course.score_to_grade(66).should eql("D")
    @course.score_to_grade(65).should eql("D")
    @course.score_to_grade(62).should eql("D-")
    @course.score_to_grade(60).should eql("F")
    @course.score_to_grade(59).should eql("F")
    @course.score_to_grade(0).should eql("F")
    @course.score_to_grade(-100).should eql("F")
  end
  
end

describe Course, "gradebook_to_csv" do
  it "should generate gradebook csv" do
    course_with_student(:active_all => true)
    @group = @course.assignment_groups.create!(:name => "Some Assignment Group", :group_weight => 100)
    @assignment = @course.assignments.create!(:title => "Some Assignment", :points_possible => 10, :assignment_group => @group)
    @assignment.grade_student(@user, :grade => "10")
    @assignment2 = @course.assignments.create!(:title => "Some Assignment 2", :points_possible => 10, :assignment_group => @group)
    @course.recompute_student_scores
    @user.reload
    @course.reload
    
    csv = @course.gradebook_to_csv
    csv.should_not be_nil
    rows = FasterCSV.parse(csv)
    rows.length.should equal(3)
    rows[0][-1].should == "Final Score"
    rows[1][-1].should == "(read only)"
    rows[2][-1].should == "50"
    rows[0][-2].should == "Current Score"
    rows[1][-2].should == "(read only)"
    rows[2][-2].should == "100"
  end
  
  it "should generate csv with final grade if enabled" do
    course_with_student(:active_all => true)
    @course.grading_standard_id = 0
    @course.save!
    @group = @course.assignment_groups.create!(:name => "Some Assignment Group", :group_weight => 100)
    @assignment = @course.assignments.create!(:title => "Some Assignment", :points_possible => 10, :assignment_group => @group)
    @assignment.grade_student(@user, :grade => "10")
    @assignment2 = @course.assignments.create!(:title => "Some Assignment 2", :points_possible => 10, :assignment_group => @group)
    @assignment2.grade_student(@user, :grade => "8")
    @course.recompute_student_scores
    @user.reload
    @course.reload
    
    csv = @course.gradebook_to_csv
    csv.should_not be_nil
    rows = FasterCSV.parse(csv)
    rows.length.should equal(3)
    rows[0][-1].should == "Final Grade"
    rows[1][-1].should == "(read only)"
    rows[2][-1].should == "A-"
    rows[0][-2].should == "Final Score"
    rows[1][-2].should == "(read only)"
    rows[2][-2].should == "90"
    rows[0][-3].should == "Current Score"
    rows[1][-3].should == "(read only)"
    rows[2][-3].should == "90"
  end
end

describe Course, "merge_into" do
  it "should merge in another course" do
    @c = Course.create!(:name => "some course")
    @c.wiki.wiki_pages.length.should == 1
    @c2 = Course.create!(:name => "another course")
    g = @c2.assignment_groups.create!(:name => "some group")
    due = Time.parse("Jan 1 2000 5:00pm")
    @c2.assignments.create!(:title => "some assignment", :assignment_group => g, :due_at => due)
    @c2.wiki.wiki_pages.create!(:title => "some page")
    @c2.quizzes.create!(:title => "some quiz")
    @c.assignments.length.should eql(0)
    @c.merge_in(@c2, :everything => true)
    @c.reload
    @c.assignment_groups.length.should eql(1)
    @c.assignment_groups.last.name.should eql(@c2.assignment_groups.last.name)
    @c.assignment_groups.last.should_not eql(@c2.assignment_groups.last)
    @c.assignments.length.should eql(1)
    @c.assignments.last.title.should eql(@c2.assignments.last.title)
    @c.assignments.last.should_not eql(@c2.assignments.last)
    @c.assignments.last.due_at.should eql(@c2.assignments.last.due_at)
    @c.wiki.wiki_pages.length.should eql(2)
    @c.wiki.wiki_pages.map(&:title).include?(@c2.wiki.wiki_pages.last.title).should be_true
    @c.wiki.wiki_pages.first.should_not eql(@c2.wiki.wiki_pages.last)
    @c.wiki.wiki_pages.last.should_not eql(@c2.wiki.wiki_pages.last)
    @c.quizzes.length.should eql(1)
    @c.quizzes.last.title.should eql(@c2.quizzes.last.title)
    @c.quizzes.last.should_not eql(@c2.quizzes.last)
  end
  
  it "should update due dates for date changes" do
    new_start = Date.parse("Jun 1 2000")
    new_end = Date.parse("Sep 1 2000")
    @c = Course.create!(:name => "some course", :start_at => new_start, :conclude_at => new_end)
    @c2 = Course.create!(:name => "another course", :start_at => Date.parse("Jan 1 2000"), :conclude_at => Date.parse("Mar 1 2000"))
    g = @c2.assignment_groups.create!(:name => "some group")
    @c2.assignments.create!(:title => "some assignment", :assignment_group => g, :due_at => Time.parse("Jan 3 2000 5:00pm"))
    @c.assignments.length.should eql(0)
    @c2.calendar_events.create!(:title => "some event", :start_at => Time.parse("Jan 11 2000 3:00pm"), :end_at => Time.parse("Jan 11 2000 4:00pm"))
    @c.calendar_events.length.should eql(0)
    @c.merge_in(@c2, :everything => true, :shift_dates => true)
    @c.reload
    @c.assignments.length.should eql(1)
    @c.assignments.last.title.should eql(@c2.assignments.last.title)
    @c.assignments.last.should_not eql(@c2.assignments.last)
    @c.assignments.last.due_at.should > new_start
    @c.assignments.last.due_at.should < new_end
    @c.assignments.last.due_at.hour.should eql(@c2.assignments.last.due_at.hour)
    @c.calendar_events.length.should eql(1)
    @c.calendar_events.last.title.should eql(@c2.calendar_events.last.title)
    @c.calendar_events.last.should_not eql(@c2.calendar_events.last)
    @c.calendar_events.last.start_at.should > new_start
    @c.calendar_events.last.start_at.should < new_end
    @c.calendar_events.last.start_at.hour.should eql(@c2.calendar_events.last.start_at.hour)
    @c.calendar_events.last.end_at.should > new_start
    @c.calendar_events.last.end_at.should < new_end
    @c.calendar_events.last.end_at.hour.should eql(@c2.calendar_events.last.end_at.hour)
  end
  
  it "should match times for changing due dates in a different time zone" do
    Time.zone = "Mountain Time (US & Canada)"
    new_start = Date.parse("Jun 1 2000")
    new_end = Date.parse("Sep 1 2000")
    @c = Course.create!(:name => "some course", :start_at => new_start, :conclude_at => new_end)
    @c2 = Course.create!(:name => "another course", :start_at => Date.parse("Jan 1 2000"), :conclude_at => Date.parse("Mar 1 2000"))
    g = @c2.assignment_groups.create!(:name => "some group")
    @c2.assignments.create!(:title => "some assignment", :assignment_group => g, :due_at => Time.parse("Jan 3 2000 5:00pm"))
    @c.assignments.length.should eql(0)
    @c2.calendar_events.create!(:title => "some event", :start_at => Time.parse("Jan 11 2000 3:00pm"), :end_at => Time.parse("Jan 11 2000 4:00pm"))
    @c.calendar_events.length.should eql(0)
    @c.merge_in(@c2, :everything => true, :shift_dates => true)
    @c.reload
    @c.assignments.length.should eql(1)
    @c.assignments.last.title.should eql(@c2.assignments.last.title)
    @c.assignments.last.should_not eql(@c2.assignments.last)
    @c.assignments.last.due_at.should > new_start
    @c.assignments.last.due_at.should < new_end
    @c.assignments.last.due_at.wday.should eql(@c2.assignments.last.due_at.wday)
    @c.assignments.last.due_at.utc.hour.should eql(@c2.assignments.last.due_at.utc.hour)
    @c.calendar_events.length.should eql(1)
    @c.calendar_events.last.title.should eql(@c2.calendar_events.last.title)
    @c.calendar_events.last.should_not eql(@c2.calendar_events.last)
    @c.calendar_events.last.start_at.should > new_start
    @c.calendar_events.last.start_at.should < new_end
    @c.calendar_events.last.start_at.wday.should eql(@c2.calendar_events.last.start_at.wday)
    @c.calendar_events.last.start_at.utc.hour.should eql(@c2.calendar_events.last.start_at.utc.hour)
    @c.calendar_events.last.end_at.should > new_start
    @c.calendar_events.last.end_at.should < new_end
    @c.calendar_events.last.end_at.wday.should eql(@c2.calendar_events.last.end_at.wday)
    @c.calendar_events.last.end_at.utc.hour.should eql(@c2.calendar_events.last.end_at.utc.hour)
    Time.zone = nil
  end
end

describe Course, "update_account_associations" do
  it "should update account associations correctly" do
    account1 = Account.create!(:name => 'first')
    account2 = Account.create!(:name => 'second')
    
    @c = Course.create!(:account => account1)
    @c.associated_accounts.length.should eql(1)
    @c.associated_accounts.first.should eql(account1)
    
    @c.account = account2
    @c.save!
    @c.reload
    @c.associated_accounts.length.should eql(1)
    @c.associated_accounts.first.should eql(account2)
  end
end

describe Course, "tabs_available" do
  it "should return the defaults if nothing specified" do
    course_with_teacher(:active_all => true)
    length = Course.default_tabs.length
    tab_ids = @course.tabs_available(@user).map{|t| t[:id] }
    tab_ids.should eql(Course.default_tabs.map{|t| t[:id] })
    tab_ids.length.should eql(length)
  end
  
  it "should overwrite the order of tabs if configured" do
    course_with_teacher(:active_all => true)
    length = Course.default_tabs.length
    @course.tab_configuration = [{'id' => Course::TAB_COLLABORATIONS}, {'id' => Course::TAB_CHAT}]
    tab_ids = @course.tabs_available(@user).map{|t| t[:id] }
    tab_ids.should eql(([Course::TAB_COLLABORATIONS, Course::TAB_CHAT] + Course.default_tabs.map{|t| t[:id] }).uniq)
    tab_ids.length.should eql(length)
  end
  
  it "should remove ids for tabs not in the default list" do
    course_with_teacher(:active_all => true)
    @course.tab_configuration = [{'id' => 912}]
    @course.tabs_available(@user).map{|t| t[:id] }.should_not be_include(912)
    tab_ids = @course.tabs_available(@user).map{|t| t[:id] }
    tab_ids.should eql(Course.default_tabs.map{|t| t[:id] })
    tab_ids.length.should > 0
    @course.tabs_available(@user).map{|t| t[:label] }.compact.length.should eql(tab_ids.length)
  end
  
  it "should hide unused tabs if not an admin" do
    course_with_student(:active_all => true)
    tab_ids = @course.tabs_available(@user).map{|t| t[:id] }
    tab_ids.should_not be_include(Course::TAB_SETTINGS)
    tab_ids.length.should > 0
  end
  
  it "should show grades tab for students" do
    course_with_student(:active_all => true)
    tab_ids = @course.tabs_available(@user).map{|t| t[:id] }
    tab_ids.should be_include(Course::TAB_GRADES)
  end
  
  it "should not show grades tab for observers" do
    course_with_student(:active_all => true)
    @student = @user
    user(:active_all => true)
    @oe = @course.enroll_user(@user, 'ObserverEnrollment')
    @oe.accept
    @user.reload
    tab_ids = @course.tabs_available(@user).map{|t| t[:id] }
    tab_ids.should_not be_include(Course::TAB_GRADES)
  end
    
  it "should show grades tab for observers if they are linked to a student" do
    course_with_student(:active_all => true)
    @student = @user
    user(:active_all => true)
    @oe = @course.enroll_user(@user, 'ObserverEnrollment')
    @oe.accept
    @oe.associated_user_id = @student.id
    @oe.save!
    @user.reload
    tab_ids = @course.tabs_available(@user).map{|t| t[:id] }
    tab_ids.should be_include(Course::TAB_GRADES)
  end
end

describe Course, "backup" do
  it "should backup to a valid data structure" do
    course_to_backup
    data = @course.backup
    data.should_not be_nil
    data.length.should > 0
    data.any?{|i| i.is_a?(Assignment)}.should eql(true)
    data.any?{|i| i.is_a?(WikiPage)}.should eql(true)
    data.any?{|i| i.is_a?(DiscussionTopic)}.should eql(true)
    data.any?{|i| i.is_a?(CalendarEvent)}.should eql(true)
  end
  
  it "should backup to a valid json string" do
    course_to_backup
    data = @course.backup_to_json
    data.should_not be_nil
    data.length.should > 0
    parse = JSON.parse(data) rescue nil
    parse.should_not be_nil
    parse.should be_is_a(Array)
    parse.length.should > 0
  end
    
  context "merge_into_course" do
    it "should merge content into another course" do
      course_model
      attachment_model
      @old_attachment = @attachment
      @old_topic = @course.discussion_topics.create!(:title => "some topic", :message => "<a href='/courses/#{@course.id}/files/#{@attachment.id}/download'>download this file</a>")
      html = @old_topic.message
      html.should match(Regexp.new("/courses/#{@course.id}/files/#{@attachment.id}/download"))
      @old_course = @course
      @new_course = course_model
      @new_course.merge_into_course(@old_course, :everything => true)
      @old_attachment.reload
      @old_attachment.cloned_item_id.should_not be_nil
      @new_attachment = @new_course.attachments.find_by_cloned_item_id(@old_attachment.cloned_item_id)
      @new_attachment.should_not be_nil
      @old_topic.reload
      @old_topic.cloned_item_id.should_not be_nil
      @new_topic = @new_course.discussion_topics.find_by_cloned_item_id(@old_topic.cloned_item_id)
      @new_topic.should_not be_nil
      html = @new_topic.message
      html.should match(Regexp.new("/courses/#{@new_course.id}/files/#{@new_attachment.id}/download"))
    end

    it "should merge locked files and retain correct html links" do
      course_model
      attachment_model
      @old_attachment = @attachment
      @old_attachment.update_attribute(:hidden, true)
      @old_attachment.reload.should be_hidden
      @old_topic = @course.discussion_topics.create!(:title => "some topic", :message => "<img src='/courses/#{@course.id}/files/#{@attachment.id}/preview'>")
      html = @old_topic.message
      html.should match(Regexp.new("/courses/#{@course.id}/files/#{@attachment.id}/preview"))
      @old_course = @course
      @new_course = course_model
      @new_course.merge_into_course(@old_course, :everything => true)
      @old_attachment.reload
      @old_attachment.cloned_item_id.should_not be_nil
      @new_attachment = @new_course.attachments.find_by_cloned_item_id(@old_attachment.cloned_item_id)
      @new_attachment.should_not be_nil
      @old_topic.reload
      @old_topic.cloned_item_id.should_not be_nil
      @new_topic = @new_course.discussion_topics.find_by_cloned_item_id(@old_topic.cloned_item_id)
      @new_topic.should_not be_nil
      html = @new_topic.message
      html.should match(Regexp.new("/courses/#{@new_course.id}/files/#{@new_attachment.id}/preview"))
    end

    it "should merge only selected content into another course" do
      course_model
      attachment_model
      @old_attachment = @attachment
      @old_topic = @course.discussion_topics.create!(:title => "some topic", :message => "<a href='/courses/#{@course.id}/files/#{@attachment.id}/download'>download this file</a>")
      html = @old_topic.message
      html.should match(Regexp.new("/courses/#{@course.id}/files/#{@attachment.id}/download"))
      @old_course = @course
      @new_course = course_model
      @new_course.merge_into_course(@old_course, :all_files => true)
      @old_attachment.reload
      @old_attachment.cloned_item_id.should_not be_nil
      @new_attachment = @new_course.attachments.find_by_cloned_item_id(@old_attachment.cloned_item_id)
      @new_attachment.should_not be_nil
      @old_topic.reload
      @old_topic.cloned_item_id.should be_nil
      @new_course.discussion_topics.count.should eql(0)
    end

    it "should migrate syllabus links on copy" do
      course_model
      @old_topic = @course.discussion_topics.create!(:title => "some topic", :message => "some text")
      @old_course = @course
      @old_course.syllabus_body = "<a href='/courses/#{@old_course.id}/discussion_topics/#{@old_topic.id}'>link</a>"
      @old_course.save!
      @new_course = course_model
      @new_course.merge_into_course(@old_course, :course_settings => true, :all_topics => true)
      @old_topic.reload
      @new_topic = @new_course.discussion_topics.find_by_cloned_item_id(@old_topic.cloned_item_id)
      @new_topic.should_not be_nil
      @old_topic.cloned_item_id.should == @new_topic.cloned_item_id
      @new_course.reload
      @new_course.syllabus_body.should match(/\/courses\/#{@new_course.id}\/discussion_topics\/#{@new_topic.id}/)
    end

    it "should merge implied content into another course" do
      course_model
      attachment_model
      @old_attachment = @attachment
      @old_topic = @course.discussion_topics.create!(:title => "some topic", :message => "<a href='/courses/#{@course.id}/files/#{@attachment.id}/download'>download this file</a>")
      html = @old_topic.message
      html.should match(Regexp.new("/courses/#{@course.id}/files/#{@attachment.id}/download"))
      @old_course = @course
      @new_course = course_model
      @new_course.merge_into_course(@old_course, :all_topics => true)
      @old_attachment.reload
      @old_attachment.cloned_item_id.should_not be_nil
      @new_attachment = @new_course.attachments.find_by_cloned_item_id(@old_attachment.cloned_item_id)
      @new_attachment.should_not be_nil
      @old_topic.reload
      @old_topic.cloned_item_id.should_not be_nil
      @new_topic = @new_course.discussion_topics.find_by_cloned_item_id(@old_topic.cloned_item_id)
      @new_topic.should_not be_nil
      html = @new_topic.message
      html.should match(Regexp.new("/courses/#{@new_course.id}/files/#{@new_attachment.id}/download"))
    end

    it "should translate links to the new context" do
      course_model
      attachment_model
      @old_attachment = @attachment
      @old_topic = @course.discussion_topics.create!(:title => "some topic", :message => "<a href='/courses/#{@course.id}/files/#{@attachment.id}/download'>download this file</a>")
      html = @old_topic.message
      html.should match(Regexp.new("/courses/#{@course.id}/files/#{@attachment.id}/download"))
      @old_course = @course
      @new_course = course_model
      @new_attachment = @old_attachment.clone_for(@new_course)
      @new_attachment.save!
      html = Course.migrate_content_links(@old_topic.message, @old_course, @new_course)
      html.should match(Regexp.new("/courses/#{@new_course.id}/files/#{@new_attachment.id}/download"))
    end
    
    it "should bring over linked files if not already brought over" do
      course_model
      attachment_model
      @old_attachment = @attachment
      @old_topic = @course.discussion_topics.create!(:title => "some topic", :message => "<a href='/courses/#{@course.id}/files/#{@attachment.id}/download'>download this file</a>")
      html = @old_topic.message
      html.should match(Regexp.new("/courses/#{@course.id}/files/#{@attachment.id}/download"))
      @old_course = @course
      @new_course = course_model
      html = Course.migrate_content_links(@old_topic.message, @old_course, @new_course)
      @old_attachment.reload
      @old_attachment.cloned_item_id.should_not be_nil
      @new_attachment = @new_course.attachments.find_by_cloned_item_id(@old_attachment.cloned_item_id)
      @new_attachment.should_not be_nil
      html.should match(Regexp.new("/courses/#{@new_course.id}/files/#{@new_attachment.id}/download"))
    end

    it "should assign the correct parent folder when the parent folder has already been created" do
      old_course = course_model
      folder = Folder.root_folders(@course).first
      folder = folder.sub_folders.create!(:context => @course, :name => 'folder_1')
      attachment_model(:folder => folder, :filename => "dummy.txt")
      folder = folder.sub_folders.create!(:context => @course, :name => 'folder_2')
      folder = folder.sub_folders.create!(:context => @course, :name => 'folder_3')
      old_attachment = attachment_model(:folder => folder, :filename => "merge.test")

      new_course = course_model

      new_course.merge_into_course(old_course, :everything => true)
      old_attachment.reload
      old_attachment.cloned_item_id.should_not be_nil
      new_attachment = new_course.attachments.find_by_cloned_item_id(old_attachment.cloned_item_id)
      new_attachment.should_not be_nil
      new_attachment.full_path.should == "course files/folder_1/folder_2/folder_3/merge.test"
      folder.reload
      new_attachment.folder.cloned_item_id.should == folder.cloned_item_id
    end
  end
  
  it "should copy learning outcomes into the new course" do
    old_course = course_model
    lo = old_course.learning_outcomes.new
    lo.context = old_course
    lo.short_description = "Lone outcome"
    lo.description = "<p>Descriptions are boring</p>"
    lo.workflow_state = 'active'
    lo.data = {:rubric_criterion=>{:mastery_points=>3, :ratings=>[{:description=>"Exceeds Expectations", :points=>5}, {:description=>"Meets Expectations", :points=>3}, {:description=>"Does Not Meet Expectations", :points=>0}], :description=>"First outcome", :points_possible=>5}}
    lo.save!
    
    old_root = LearningOutcomeGroup.default_for(old_course)
    old_root.add_item(lo)
    
    lo_g = old_course.learning_outcome_groups.new
    lo_g.context = old_course
    lo_g.title = "Lone outcome group"
    lo_g.description = "<p>Groupage</p>"
    lo_g.save!
    old_root.add_item(lo_g)
    
    lo2 = old_course.learning_outcomes.new
    lo2.context = old_course
    lo2.short_description = "outcome in group"
    lo2.workflow_state = 'active'
    lo2.data = {:rubric_criterion=>{:mastery_points=>2, :ratings=>[{:description=>"e", :points=>50}, {:description=>"me", :points=>2}, {:description=>"Does Not Meet Expectations", :points=>0.5}], :description=>"First outcome", :points_possible=>5}}
    lo2.save!
    lo_g.add_item(lo2)
    old_root.reload
    
    # copy outcomes into new course
    new_course = course_model
    new_root = LearningOutcomeGroup.default_for(new_course)
    new_course.merge_into_course(old_course, :all_outcomes => true)
    
    new_course.learning_outcomes.count.should == old_course.learning_outcomes.count
    new_course.learning_outcome_groups.count.should == old_course.learning_outcome_groups.count
    new_root.sorted_content.count.should == old_root.sorted_content.count
    
    lo_2 = new_root.sorted_content.first
    lo_2.short_description.should == lo.short_description
    lo_2.description.should == lo.description
    lo_2.data.should == lo.data
    
    lo_g_2 = new_root.sorted_content.last
    lo_g_2.title.should == lo_g.title
    lo_g_2.description.should == lo_g.description
    lo_g_2.sorted_content.length.should == 1
    lo_g_2.root_learning_outcome_group_id.should == new_root.id
    lo_g_2.learning_outcome_group_id.should == new_root.id
    
    lo_2 = lo_g_2.sorted_content.first
    lo_2.short_description.should == lo2.short_description
    lo_2.description.should == lo2.description
    lo_2.data.should == lo2.data
  end
  
end

def course_to_backup
  @course = course
  group = @course.assignment_groups.create!(:name => "Some Assignment Group")
  @course.assignments.create!(:title => "Some Assignment", :assignment_group => group)
  @course.calendar_events.create!(:title => "Some Event", :start_at => Time.now, :end_at => Time.now)
  @course.wiki.wiki_pages.create!(:title => "Some Page")
  topic = @course.discussion_topics.create!(:title => "Some Discussion")
  topic.discussion_entries.create!(:message => "just a test")
  @course
end

describe Course, 'grade_publishing' do
  before(:each) do
    @course = Course.new
  end
  
  after(:each) do
    Course.valid_grade_export_types.delete("test_export")
    PluginSetting.settings_for_plugin('grade_export')[:format_type] = "instructure_csv"
    PluginSetting.settings_for_plugin('grade_export')[:enabled] = "false"
    PluginSetting.settings_for_plugin('grade_export')[:publish_endpoint] = ""
    PluginSetting.settings_for_plugin('grade_export')[:wait_for_success] = "no"
  end
  
  def start_server
    post_lines = []
    server = TCPServer.open(0)
    port = server.addr[1]
    post_lines = []
    server_thread = Thread.new(server, post_lines) do |server, post_lines|
      client = server.accept
      content_length = 0
      loop do
        line = client.readline
        post_lines << line.strip unless line =~ /\AHost: localhost:|\AContent-Length: /
        content_length = line.split(":")[1].to_i if line.strip =~ /\AContent-Length: [0-9]+\z/
        if line.strip.blank?
          post_lines << client.read(content_length)
          break
        end
      end
      client.puts("HTTP/1.1 200 OK\nContent-Length: 0\n\n")
      client.close
      server.close
    end
    return server, server_thread, post_lines
  end

  it 'should pass a quick sanity check' do
    user = User.new
    Course.valid_grade_export_types["test_export"] = {
        :name => "test export",
        :callback => lambda {|course, enrollments, publishing_pseudonym|
          course.should == @course
          publishing_pseudonym.should == nil
          return [[[], "test-jt-data", "application/jtmimetype"]], []
        }}
    PluginSetting.settings_for_plugin('grade_export')[:enabled] = "true"
    PluginSetting.settings_for_plugin('grade_export')[:format_type] = "test_export"
    PluginSetting.settings_for_plugin('grade_export')[:wait_for_success] = "no"
    server, server_thread, post_lines = start_server
    PluginSetting.settings_for_plugin('grade_export')[:publish_endpoint] = "http://localhost:#{server.addr[1]}/endpoint"

    @course.grading_standard_id = 0
    @course.publish_final_grades(user)
    server_thread.join
    post_lines.should == [
        "POST /endpoint HTTP/1.1",
        "Accept: */*",
        "Content-Type: application/jtmimetype",
        "",
        "test-jt-data"]
  end
  
  it 'should publish csv' do
    user = User.new
    PluginSetting.settings_for_plugin('grade_export')[:enabled] = "true"
    PluginSetting.settings_for_plugin('grade_export')[:format_type] = "instructure_csv"
    PluginSetting.settings_for_plugin('grade_export')[:wait_for_success] = "no"
    server, server_thread, post_lines = start_server
    PluginSetting.settings_for_plugin('grade_export')[:publish_endpoint] = "http://localhost:#{server.addr[1]}/endpoint"
    @course.grading_standard_id = 0
    @course.publish_final_grades(user)
    server_thread.join
    post_lines.should == [
        "POST /endpoint HTTP/1.1",
        "Accept: */*",
        "Content-Type: text/csv",
        "",
        "publisher_id,publisher_sis_id,section_id,section_sis_id,student_id," +
        "student_sis_id,enrollment_id,enrollment_status,grade,score\n"]
  end

  it 'should publish grades' do
    process_csv_data_cleanly(
      "user_id,login_id,password,first_name,last_name,email,status",
      "T1,Teacher1,,T,1,t1@example.com,active",
      "S1,Student1,,S,1,s1@example.com,active",
      "S2,Student2,,S,2,s2@example.com,active",
      "S3,Student3,,S,3,s3@example.com,active",
      "S4,Student4,,S,4,s4@example.com,active",
      "S5,Student5,,S,5,s5@example.com,active",
      "S6,Student6,,S,6,s6@example.com,active")
    process_csv_data_cleanly(
      "course_id,short_name,long_name,account_id,term_id,status",
      "C1,C1,C1,,,active")
    @course = Course.find_by_sis_source_id("C1")
    @course.assignment_groups.create(:name => "Assignments")
    process_csv_data_cleanly(
      "section_id,course_id,name,status,start_date,end_date",
      "S1,C1,S1,active,,",
      "S2,C1,S2,active,,",
      "S3,C1,S3,active,,",
      "S4,C1,S4,active,,")
    process_csv_data_cleanly(
      "course_id,user_id,role,section_id,status",
      ",T1,teacher,S1,active",
      ",S1,student,S1,active",
      ",S2,student,S2,active",
      ",S3,student,S2,active",
      ",S4,student,S1,active",
      ",S5,student,S3,active",
      ",S6,student,S4,active")
    a1 = @course.assignments.create!(:title => "A1", :points_possible => 10)
    a2 = @course.assignments.create!(:title => "A2", :points_possible => 10)
    
    def getpseudonym(user_sis_id)
      pseudo = Pseudonym.find_by_sis_user_id(user_sis_id)
      pseudo.should_not be_nil
      pseudo
    end
    
    def getuser(user_sis_id)
      user = getpseudonym(user_sis_id).user
      user.should_not be_nil
      user
    end
    
    def getsection(section_sis_id)
      section = CourseSection.find_by_sis_source_id(section_sis_id)
      section.should_not be_nil
      section
    end
    
    def getenroll(user_sis_id, section_sis_id)
      e = Enrollment.find_by_user_id_and_course_section_id(getuser(user_sis_id).id, getsection(section_sis_id).id)
      e.should_not be_nil
      e
    end
    
    a1.grade_student(getuser("S1"), { :grade => "6", :grader => getuser("T1") })
    a1.grade_student(getuser("S2"), { :grade => "6", :grader => getuser("T1") })
    a1.grade_student(getuser("S3"), { :grade => "7", :grader => getuser("T1") })
    a1.grade_student(getuser("S5"), { :grade => "7", :grader => getuser("T1") })
    a1.grade_student(getuser("S6"), { :grade => "8", :grader => getuser("T1") })
    a2.grade_student(getuser("S1"), { :grade => "8", :grader => getuser("T1") })
    a2.grade_student(getuser("S2"), { :grade => "9", :grader => getuser("T1") })
    a2.grade_student(getuser("S3"), { :grade => "9", :grader => getuser("T1") })
    a2.grade_student(getuser("S5"), { :grade => "10", :grader => getuser("T1") })
    a2.grade_student(getuser("S6"), { :grade => "10", :grader => getuser("T1") })
    
    stud5, stud6, sec4 = nil, nil, nil
    Pseudonym.find_by_sis_user_id("S5").tap do |p|
      stud5 = p
      p.sis_user_id = nil
      p.sis_source_id = nil
      p.save
    end
    
    Pseudonym.find_by_sis_user_id("S6").tap do |p|
      stud6 = p
      p.sis_user_id = nil
      p.sis_source_id = nil
      p.save
    end
    
    getsection("S4").tap do |s|
      sec4 = s
      sec4id = s.sis_source_id
      s.sis_source_id = nil
      s.save
    end
    
    GradeCalculator.recompute_final_score(["S1", "S2", "S3", "S4"].map{|x|getuser(x).id}, @course.id)
    @course.reload
    
    teacher = Pseudonym.find_by_sis_user_id("T1")
    teacher.should_not be_nil
    
    PluginSetting.settings_for_plugin('grade_export')[:enabled] = "true"
    PluginSetting.settings_for_plugin('grade_export')[:format_type] = "instructure_csv"
    PluginSetting.settings_for_plugin('grade_export')[:wait_for_success] = "no"
    server, server_thread, post_lines = start_server
    PluginSetting.settings_for_plugin('grade_export')[:publish_endpoint] = "http://localhost:#{server.addr[1]}/endpoint"
    @course.publish_final_grades(teacher.user)
    server_thread.join
    post_lines.should == [
        "POST /endpoint HTTP/1.1",
        "Accept: */*",
        "Content-Type: text/csv",
        "",
        "publisher_id,publisher_sis_id,section_id,section_sis_id,student_id," +
        "student_sis_id,enrollment_id,enrollment_status,grade,score\n" +
        "#{teacher.id},T1,#{getsection("S1").id},S1,#{getpseudonym("S1").id},S1,#{getenroll("S1", "S1").id},active,\"\",70\n" +
        "#{teacher.id},T1,#{getsection("S2").id},S2,#{getpseudonym("S2").id},S2,#{getenroll("S2", "S2").id},active,\"\",75\n" +
        "#{teacher.id},T1,#{getsection("S2").id},S2,#{getpseudonym("S3").id},S3,#{getenroll("S3", "S2").id},active,\"\",80\n" +
        "#{teacher.id},T1,#{getsection("S1").id},S1,#{getpseudonym("S4").id},S4,#{getenroll("S4", "S1").id},active,\"\",0\n" + 
        "#{teacher.id},T1,#{getsection("S3").id},S3,#{stud5.id},,#{Enrollment.find_by_user_id_and_course_section_id(stud5.user.id, getsection("S3").id).id},active,\"\",85\n" + 
        "#{teacher.id},T1,#{sec4.id},,#{stud6.id},,#{Enrollment.find_by_user_id_and_course_section_id(stud6.user.id, sec4.id).id},active,\"\",90\n"]
    @course.grading_standard_id = 0
    @course.save
    server, server_thread, post_lines = start_server
    PluginSetting.settings_for_plugin('grade_export')[:publish_endpoint] = "http://localhost:#{server.addr[1]}/endpoint"
    @course.publish_final_grades(teacher.user)
    server_thread.join
    post_lines.should == [
        "POST /endpoint HTTP/1.1",
        "Accept: */*",
        "Content-Type: text/csv",
        "",
        "publisher_id,publisher_sis_id,section_id,section_sis_id,student_id," +
        "student_sis_id,enrollment_id,enrollment_status,grade,score\n" +
        "#{teacher.id},T1,#{getsection("S1").id},S1,#{getpseudonym("S1").id},S1,#{getenroll("S1", "S1").id},active,C-,70\n" +
        "#{teacher.id},T1,#{getsection("S2").id},S2,#{getpseudonym("S2").id},S2,#{getenroll("S2", "S2").id},active,C,75\n" +
        "#{teacher.id},T1,#{getsection("S2").id},S2,#{getpseudonym("S3").id},S3,#{getenroll("S3", "S2").id},active,B-,80\n" +
        "#{teacher.id},T1,#{getsection("S1").id},S1,#{getpseudonym("S4").id},S4,#{getenroll("S4", "S1").id},active,F,0\n" + 
        "#{teacher.id},T1,#{getsection("S3").id},S3,#{stud5.id},,#{Enrollment.find_by_user_id_and_course_section_id(stud5.user.id, getsection("S3").id).id},active,B,85\n" + 
        "#{teacher.id},T1,#{sec4.id},,#{stud6.id},,#{Enrollment.find_by_user_id_and_course_section_id(stud6.user.id, sec4.id).id},active,A-,90\n"]
  end
  
end

describe Course, 'scoping' do
  it 'should search by multiple fields' do
    c1 = Course.new
    c1.root_account = Account.create
    c1.name = "name1"
    c1.sis_source_id = "sisid1"
    c1.course_code = "code1"
    c1.save
    c2 = Course.new
    c2.root_account = Account.create
    c2.name = "name2"
    c2.course_code = "code2"
    c2.sis_source_id = "sisid2"
    c2.save
    Course.name_like("name1").map(&:id).should == [c1.id]
    Course.name_like("sisid2").map(&:id).should == [c2.id]
    Course.name_like("code1").map(&:id).should == [c1.id]    
  end
end

describe Course, "manageable_by_user" do
  it "should include courses associated with the user's active accounts" do
    account = Account.create!
    sub_account = Account.create!(:parent_account => account)
    sub_sub_account = Account.create!(:parent_account => sub_account)
    user = account_admin_user(:account => sub_account)
    course = Course.create!(:account => sub_sub_account)

    Course.manageable_by_user(user.id).map{ |c| c.id }.should be_include(course.id)
  end

  it "should include courses the user is actively enrolled in as a teacher" do
    course = Course.create
    user = user_with_pseudonym
    course.enroll_teacher(user)
    e = course.teacher_enrollments.first
    e.accept

    Course.manageable_by_user(user.id).map{ |c| c.id }.should be_include(course.id)
  end

  it "should include courses the user is actively enrolled in as a ta" do
    course = Course.create
    user = user_with_pseudonym
    course.enroll_ta(user)
    e = course.ta_enrollments.first
    e.accept

    Course.manageable_by_user(user.id).map{ |c| c.id }.should be_include(course.id)
  end

  it "should not include courses the user is enrolled in when the enrollment is non-active" do
    course = Course.create
    user = user_with_pseudonym
    course.enroll_teacher(user)
    e = course.teacher_enrollments.first

    # it's only invited at this point
    Course.manageable_by_user(user.id).should be_empty

    e.destroy
    Course.manageable_by_user(user.id).should be_empty
  end

  it "should not include aborted or deleted courses the user was enrolled in" do
    course = Course.create
    user = user_with_pseudonym
    course.enroll_teacher(user)
    e = course.teacher_enrollments.first
    e.accept

    course.destroy
    Course.manageable_by_user(user.id).should be_empty
  end
end
