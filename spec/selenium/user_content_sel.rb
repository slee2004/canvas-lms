require File.expand_path(File.dirname(__FILE__) + '/common')

shared_examples_for "user_content selenium tests" do
  it_should_behave_like "in-process server selenium tests"

  before(:each) do
    course_with_student_logged_in(:active_all => true)
  end

  it "should serve embed tags from a safefiles iframe" do
    factory_with_protected_attributes(Announcement, :context => @course, :title => "hey all read this k", :message => message_body)
    get "/"
    uri = nil
    name = driver.find_elements(:class_name, "user_content_iframe").first.attribute('name')
    driver.switch_to.frame(name)
    keep_trying_until {
      driver.current_url.should match("/object_snippet")
    }
    html = Nokogiri::HTML(driver.page_source)
    obj = html.at_css('object')
    obj.should_not be_nil
    obj['data'].should == '/javascripts/swfobject/test.swf'
  end

  it "should iframe calendar json requests" do
    e = factory_with_protected_attributes(CalendarEvent, :context => @course, :title => "super fun party", :description => message_body, :start_at => 5.minutes.ago, :end_at => 5.minutes.from_now)
    get "/calendar"
    driver.find_elements(:class_name, "user_content_iframe").size.should == 0
    event_el = keep_trying_until { driver.find_element(:id, "event_calendar_event_#{e.id}") }
    event_el.find_element(:tag_name, 'a').click
    name = keep_trying_until { driver.find_elements(:class_name, "user_content_iframe").first.attribute('name') }
    driver.switch_to.frame(name)
    keep_trying_until {
      driver.current_url.should match("/object_snippet")
    }
    html = Nokogiri::HTML(driver.page_source)
    obj = html.at_css('object')
    obj.should_not be_nil
    obj['data'].should == '/javascripts/swfobject/test.swf'
  end

  def message_body
    <<-MESSAGE
<p>flash:</p>
<p><object width="425" height="350" data="/javascripts/swfobject/test.swf" type="application/x-shockwave-flash"><param name="wmode" value="transparent" /><param name="src" value="/javascripts/swfobject/test.swf" /></object></p>
MESSAGE
  end
end

describe "user_content Windows-Firefox-Tests" do
  it_should_behave_like "user_content selenium tests"
end
