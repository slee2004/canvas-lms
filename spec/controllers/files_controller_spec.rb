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

require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe FilesController do
  def course_folder
    @folder = @course.folders.create!(:name => "a folder", :workflow_state => "visible")
  end
  def io
    require 'action_controller'
    require 'action_controller/test_process.rb'
    ActionController::TestUploadedFile.new(File.expand_path(File.dirname(__FILE__) + '/../fixtures/scribd_docs/doc.doc'), 'application/msword', true)
  end
  def course_file
    @file = factory_with_protected_attributes(@course.attachments, :uploaded_data => io)
  end
  
  def user_file
    @file = factory_with_protected_attributes(@user.attachments, :uploaded_data => io)
  end
  
  def folder_file
    @file = @folder.active_file_attachments.build(:uploaded_data => io)
    @file.context = @course
    @file.save!
    @file
  end
  
  def file_in_a_module
    course_with_student_logged_in(:active_all => true)
    @file = factory_with_protected_attributes(@course.attachments, :uploaded_data => io)
    @module = @course.context_modules.create!(:name => "module")
    @tag = @module.add_item({:type => 'attachment', :id => @file.id}) 
    @module.reload
    hash = {}
    hash[@tag.id.to_s] = {:type => 'must_view'}
    @module.completion_requirements = hash
    @module.save!
    @module.evaluate_for(@user, true, true).state.should eql(:unlocked)
  end
  
  def file_with_path(path)
    components = path.split('/')
    folder = nil
    while components.size > 1
      component = components.shift
      folder = @course.folders.find_by_name(component)
      folder ||= @course.folders.create!(:name => component, :workflow_state => "visible", :parent_folder => folder)
    end
    filename = components.shift
    @file = folder.active_file_attachments.build(:filename => filename, :uploaded_data => io)
    @file.context = @course
    @file.save!
    @file
  end
  
  describe "GET 'quota'" do
    it "should require authorization" do
      course_with_teacher(:active_all => true)
      get 'quota', :course_id => @course.id
      assert_unauthorized
    end
    
    it "should assign variables for course quota" do
      course_with_teacher_logged_in(:active_all => true)
      get 'quota', :course_id => @course.id
      assigns[:quota].should_not be_nil
      response.should be_success
    end
    
    it "should assign variables for user quota" do
      user(:active_all => true)
      user_session(@user)
      get 'quota', :user_id => @user.id
      assigns[:quota].should_not be_nil
      response.should be_success
    end
  end
  
  describe "GET 'index'" do
    it "should require authorization" do
      course_with_teacher(:active_all => true)
      get 'index', :course_id => @course.id
      assert_unauthorized
    end
    
    it "should redirect 'disabled', if disabled by the teacher" do
      course_with_student_logged_in(:active_all => true)
      @course.update_attribute(:tab_configuration, [{'id'=>11,'hidden'=>true}])
      get 'index', :course_id => @course.id
      response.should be_redirect
      flash[:notice].should match(/That page has been disabled/)
    end
    
    it "should assign variables" do
      course_with_teacher_logged_in(:active_all => true)
      get 'index', :course_id => @course.id
      response.should be_success
      assigns[:contexts].should_not be_nil
      assigns[:contexts][0].should eql(@course)
    end
    
    it "should return data for sub_folder if specified" do
      course_with_teacher_logged_in(:active_all => true)
      f1 = course_folder
      a1 = folder_file
      get 'index', :course_id => @course.id, :format => 'json'
      response.should be_success
      data = JSON.parse(response.body) rescue nil
      data.should_not be_nil
      data['contexts'].length.should eql(1)
      data['contexts'][0]['course']['id'].should eql(@course.id)
      
      f2 = course_folder
      a2 = folder_file
      get 'index', :course_id => @course.id, :folder_id => f2.id
      response.should be_success
      assigns[:current_folder].should eql(f2)
      assigns[:current_attachments].should_not be_nil
      assigns[:current_attachments].should_not be_empty
      assigns[:current_attachments][0].should eql(a2)
    end
    
    it "should work for a user context, too" do
      user(:active_all => true)
      user_session(@user)
      get 'index', :user_id => @user.id
      response.should be_success
    end
    
    it "should work for a group context, too" do
      group_with_user
      @group.add_user(@user)
      user_session(@user)
      get 'index', :group_id => @group.id
      response.should be_success
    end
  end
  
  describe "GET 'show'" do
    it "should require authorization" do
      course_with_teacher(:active_all => true)
      course_file
      get 'show', :course_id => @course.id, :id => @file.id
    end
    
    it "should assign variables" do
      course_with_teacher_logged_in(:active_all => true)
      course_file
      get 'show', :course_id => @course.id, :id => @file.id
      response.should be_success
      assigns[:attachment].should_not be_nil
      assigns[:attachment].should eql(@file)
    end
    
    it "should redirect for download" do
      course_with_teacher_logged_in(:active_all => true)
      course_file
      begin
        get 'show', :course_id => @course.id, :id => @file.id, :download => 1
      rescue => e
        e.to_s.should eql("Not Found")
      end
    end
    
    it "should allow concluded teachers to read and download files" do
      course_with_teacher_logged_in(:active_all => true)
      course_file
      @enrollment.conclude
      get 'show', :course_id => @course.id, :id => @file.id
      response.should be_success
      begin
        get 'show', :course_id => @course.id, :id => @file.id, :download => 1
      rescue => e
        e.to_s.should eql("Not Found")
      end
    end
    
    it "should allow concluded students to read and download files" do
      course_with_student_logged_in(:active_all => true)
      course_file
      @enrollment.conclude
      get 'show', :course_id => @course.id, :id => @file.id
      response.should be_success
      begin
        get 'show', :course_id => @course.id, :id => @file.id, :download => 1
      rescue => e
        e.to_s.should eql("Not Found")
      end
    end
    
    it "should mark files as viewed for module progressions if the file is downloaded" do
      file_in_a_module
      get 'show', :course_id => @course.id, :id => @file.id, :download => 1
      @module.reload
      @module.evaluate_for(@user, true, true).state.should eql(:completed)
    end
    
    it "should not mark a file as viewed for module progressions if the file is locked" do
      file_in_a_module
      @file.locked = true
      @file.save!
      get 'show', :course_id => @course.id, :id => @file.id, :download => 1
      @module.reload
      @module.evaluate_for(@user, true, true).state.should eql(:unlocked)
    end
    
    it "should not mark a file as viewed for module progressions just because the files#show view is rendered" do
      file_in_a_module
      @file.locked = true
      @file.save!
      get 'show', :course_id => @course.id, :id => @file.id
      @module.reload
      @module.evaluate_for(@user, true, true).state.should eql(:unlocked)
    end
    
    it "should mark files as viewed for module progressions if the file is previewed inline" do
      file_in_a_module
      get 'show', :course_id => @course.id, :id => @file.id, :inline => 1
      response.body.should eql({:ok => true}.to_json)
      @module.reload
      @module.evaluate_for(@user, true, true).state.should eql(:completed)
    end
    
    it "should mark files as viewed for module progressions if the file data is requested and it includes the scribd_doc data" do
      file_in_a_module
      @file.scribd_doc = Scribd::Document.new
      @file.save!
      get 'show', :course_id => @course.id, :id => @file.id, :format => :json
      @module.reload
      @module.evaluate_for(@user, true, true).state.should eql(:completed)
    end
    
    it "should not mark files as viewed for module progressions if the file data is requested and it doesn't include the scribd_doc data (meaning it got viewed in scribd inline) and google docs preview is disabled" do
      file_in_a_module
      @file.scribd_doc = nil
      @file.save!
      
      # turn off google docs previews for this acccount so we can isolate testing just scribd.
      account = @module.context.account
      account.disable_service(:google_docs_previews)
      account.save!
      
      get 'show', :course_id => @course.id, :id => @file.id, :format => :json
      @module.reload
      @module.evaluate_for(@user, true, true).state.should eql(:unlocked)
    end

  end

  describe "GET 'show_relative'" do
    it "should find files by relative path" do
      course_with_teacher_logged_in(:active_all => true)
      
      file_in_a_module
      get "show_relative", :course_id => @course.id, :file_path => @file.full_display_path
      response.should be_redirect
      get "show_relative", :course_id => @course.id, :file_path => @file.full_path
      response.should be_redirect
      
      def test_path(path)
        file_with_path(path)
        get "show_relative", :course_id => @course.id, :file_path => @file.full_display_path
        response.should be_redirect
        get "show_relative", :course_id => @course.id, :file_path => @file.full_path
        response.should be_redirect
      end
      
      test_path("course files/unfiled/test1.txt")
      test_path("course files/blah")
      test_path("course files/a/b/c%20dude/d/e/f.gif")
    end

    it "should fail if the file path doesn't match" do
      course_with_teacher_logged_in(:active_all => true)
      file_in_a_module
      proc { get "show_relative", :course_id => @course.id, :file_path => @file.full_display_path+"blah" }.should raise_error(ActiveRecord::RecordNotFound)
      proc { get "show_relative", :file_id => @file.id, :course_id => @course.id, :file_path => @file.full_display_path+"blah" }.should raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "GET 'new'" do
    it "should require authorization" do
      course_with_teacher(:active_all => true)
      get 'new', :course_id => @course.id
      assert_unauthorized
    end
    
    it "should assign variables" do
      course_with_teacher_logged_in(:active_all => true)
      get 'new', :course_id => @course.id
      assigns[:attachment].should_not be_nil
    end
  end
  
  describe "POST 'create'" do
    it "should require authorization" do
      course_with_teacher(:active_all => true)
      post 'create', :course_id => @course.id, :attachment => {:display_name => "bob"}
      assert_unauthorized
    end
    
    it "should create file" do
      course_with_teacher_logged_in(:active_all => true)
      post 'create', :course_id => @course.id, :attachment => {:display_name => "bob", :uploaded_data => io}
      response.should be_redirect
      assigns[:attachment].should_not be_nil
      assigns[:attachment].display_name.should eql("bob")
    end
  end
  
  describe "PUT 'update'" do
    it "should require authorization" do
      course_with_teacher(:active_all => true)
      course_file
      put 'update', :course_id => @course.id, :id => @file.id
      assert_unauthorized
    end
    
    it "should update file" do
      course_with_teacher_logged_in(:active_all => true)
      course_file
      # TODO: attachment_fu is not playing nice with this test.
      # TODO: attachment_fu gets mad if there's no actual file
      # put 'update', :course_id => @course.id, :id => @file.id, :attachment => {:display_name => "new name", :uploaded_data => nil}
      # response.should be_redirect
      # assigns[:attachment].should eql(@file)
      # assigns[:attachment].display_name.should eql("new name")
    end
    
    it "should move file into a folder" do
      course_with_teacher_logged_in(:active_all => true)
      course_file
      course_folder
      
      put 'update', :course_id => @course.id, :id => @file.id, :attachment => { :folder_id => @folder.id }, :format => 'json'
      response.should be_success
      
      @file.reload
      @file.folder.should eql(@folder)
    end
  end
  
  describe "DELETE 'destroy'" do
    it "should require authorization" do
      course_with_teacher(:active_all => true)
      course_file
      delete 'destroy', :course_id => @course.id, :id => @file.id
    end
    
    it "should delete file" do
      course_with_teacher_logged_in(:active_all => true)
      course_file
      # TODO: attachment_fu is not playing nice with this test
      # delete 'destroy', :course_id => @course.id, :id => @file.id
      # response.should be_redirect
      # assigns[:attachment].should eql(@file)
      # assigns[:attachment].should be_frozen
    end
  end
  
  describe "POST 'create_pending'" do
    it "should require authorization" do
      course_with_teacher(:active_all => true)
      post 'create_pending', {:attachment => {:context_code => @course.asset_string}}
      assert_unauthorized
    end
    
    it "should create file placeholder (in local mode)" do
      Attachment.stub!(:s3_storage?).and_return(false)
      Attachment.stub!(:local_storage?).and_return(true)
      Attachment.local_storage?.should eql(true)
      Attachment.s3_storage?.should eql(false)
      course_with_teacher_logged_in(:active_all => true)
      post 'create_pending', {:attachment => {
        :context_code => @course.asset_string,
        :filename => "bob.txt"
      }}
      response.should be_success
      assigns[:attachment].should_not be_nil
      assigns[:attachment].id.should_not be_nil
      json = JSON.parse(response.body) rescue nil
      json.should_not be_nil
      json['id'].should eql(assigns[:attachment].id)
      json['upload_url'].should_not be_nil
      json['upload_params'].should_not be_nil
      json['upload_params'].should_not be_empty
      json['remote_url'].should eql(false)
    end
    
    it "should create file placeholder (in s3 mode)" do
      Attachment.stub!(:s3_storage?).and_return(true)
      Attachment.stub!(:local_storage?).and_return(false)
      conn = mock(AWS::S3::Connection)
      AWS::S3::Base.stub!(:connection).and_return(conn)
      conn.stub!(:access_key_id).and_return('stub_id')
      conn.stub!(:secret_access_key).and_return('stub_key')

      Attachment.s3_storage?.should eql(true)
      Attachment.local_storage?.should eql(false)
      course_with_teacher_logged_in(:active_all => true)
      post 'create_pending', {:attachment => {
        :context_code => @course.asset_string,
        :filename => "bob.txt"
      }}
      response.should be_success
      assigns[:attachment].should_not be_nil
      assigns[:attachment].id.should_not be_nil
      json = JSON.parse(response.body) rescue nil
      json.should_not be_nil
      json['id'].should eql(assigns[:attachment].id)
      json['upload_url'].should_not be_nil
      json['upload_params'].should be_present
      json['upload_params']['AWSAccessKeyId'].should == 'stub_id'
      json['remote_url'].should eql(true)
    end
    
    it "should not allow going over quota for file uploads" do
      Attachment.stub!(:s3_storage?).and_return(true)
      Attachment.stub!(:local_storage?).and_return(false)
      conn = mock(AWS::S3::Connection)
      AWS::S3::Base.stub!(:connection).and_return(conn)
      conn.stub!(:access_key_id).and_return('stub_id')
      conn.stub!(:secret_access_key).and_return('stub_key')

      Attachment.s3_storage?.should eql(true)
      Attachment.local_storage?.should eql(false)
      course_with_student_logged_in(:active_all => true)
      Setting.set('user_default_quota', -1)
      post 'create_pending', {:attachment => {
        :context_code => @user.asset_string,
        :filename => "bob.txt"
      }}
      response.should be_redirect
      assigns[:quota_used].should > assigns[:quota]
    end
    
    it "should allow going over quota for homework submissions" do
      Attachment.stub!(:s3_storage?).and_return(true)
      Attachment.stub!(:local_storage?).and_return(false)
      conn = mock(AWS::S3::Connection)
      AWS::S3::Base.stub!(:connection).and_return(conn)
      conn.stub!(:access_key_id).and_return('stub_id')
      conn.stub!(:secret_access_key).and_return('stub_key')

      Attachment.s3_storage?.should eql(true)
      Attachment.local_storage?.should eql(false)
      course_with_student_logged_in(:active_all => true)
      @assignment = @course.assignments.create!(:title => 'upload_assignment', :submission_types => 'online_upload')
      Setting.set('user_default_quota', -1)
      post 'create_pending', {:attachment => {
        :context_code => @assignment.context_code,
        :asset_string => @assignment.asset_string,
        :intent => 'submit',
        :filename => "bob.txt"
      }, :format => :json}
      response.should be_success
      assigns[:attachment].should_not be_nil
      assigns[:attachment].id.should_not be_nil
      json = JSON.parse(response.body) rescue nil
      json.should_not be_nil
      json['id'].should eql(assigns[:attachment].id)
      json['upload_url'].should_not be_nil
      json['upload_params'].should be_present
      json['upload_params']['AWSAccessKeyId'].should == 'stub_id'
      json['remote_url'].should eql(true)
    end
  end
  
  describe "POST 's3_success'" do
  end
  
end
