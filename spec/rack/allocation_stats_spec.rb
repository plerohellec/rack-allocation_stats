# Copyright 2013 Google Inc. All Rights Reserved.
# Licensed under the Apache License, Version 2.0, found in the LICENSE file.

require_relative "../spec_helper"

describe Rack::AllocationStats do
  before do
    @app = HelloWorldApp.new
    @vanilla_request_env = Rack::MockRequest.env_for("/")
    @traced_request_env  = Rack::MockRequest.env_for("/", :params => "ras[trace]=true")
  end

  it "returns something when called with a tracing request" do
    status, headers, _ = Rack::AllocationStats.new(@app).call(@traced_request_env)

    expect(headers["Content-Type"]).to eq "text/plain"
    expect(status).to be 200
  end

  it "does not interfere when not a trace request" do
    _, _, body = Rack::AllocationStats.new(@app).call(@vanilla_request_env)

    expect(body).to eq ["Hello Rack!"]
  end

  it "deletes ras[] params before hitting next app" do
    allocation_stats = Rack::AllocationStats.new(@app)

    @app.should_receive(:call).with(query_string({}))

    status, headers, _ = allocation_stats.call(@traced_request_env)
  end

  it "returns the correct body when called with a tracing request" do
    _, _, body = Rack::AllocationStats.new(@app).call(@traced_request_env)

    expected_body = [
      "#{HelloWorldApp::FULL_PATH}:#{@app.allocating_lines[1]}  allocated    2 `String`\n",
      "#{HelloWorldApp::FULL_PATH}:#{@app.allocating_lines[1]}  allocated    1 `Array<String>`\n",
      "#{HelloWorldApp::FULL_PATH}:#{@app.allocating_lines[1]}  allocated    1 `Array<Fixnum,Hash,Array>`\n",
      "#{HelloWorldApp::FULL_PATH}:#{@app.allocating_lines[1]}  allocated    1 `Hash`\n",
      "#{HelloWorldApp::FULL_PATH}:#{@app.allocating_lines[0]}  allocated    1 `String`\n"
    ]

    expect(body).to include(expected_body[0])
    expect(body).to include(expected_body[1])
    expect(body).to include(expected_body[2])
    expect(body).to include(expected_body[3])
    expect(body).to include(expected_body[4])
  end

  it "returns the correct body when called with alias_paths" do
    request_env  = Rack::MockRequest.env_for("/", :params => "ras[trace]=true&ras[alias_paths]=true")
    _, _, body = Rack::AllocationStats.new(@app).call(request_env)

    expected_body = [
      "<PWD>/spec/hello_world_app.rb:#{@app.allocating_lines[1]}  allocated    2 `String`\n",
      "<PWD>/spec/hello_world_app.rb:#{@app.allocating_lines[1]}  allocated    1 `Array<String>`\n",
      "<PWD>/spec/hello_world_app.rb:#{@app.allocating_lines[1]}  allocated    1 `Array<Fixnum,Hash,Array>`\n",
      "<PWD>/spec/hello_world_app.rb:#{@app.allocating_lines[1]}  allocated    1 `Hash`\n",
      "<PWD>/spec/hello_world_app.rb:#{@app.allocating_lines[0]}  allocated    1 `String`\n"
    ]

    expect(body).to include(expected_body[0])
    expect(body).to include(expected_body[1])
    expect(body).to include(expected_body[2])
    expect(body).to include(expected_body[3])
    expect(body).to include(expected_body[4])
  end

  it "returns correct body when called with a tracing request with times" do
    request_env = Rack::MockRequest.env_for("/", :params => "ras[trace]=true&ras[times]=4")
    _, _, body = Rack::AllocationStats.new(@app).call(request_env)

    expected_body = [
      "#{HelloWorldApp::FULL_PATH}:#{@app.allocating_lines[1]}  allocated    8 `String`\n",
      "#{HelloWorldApp::FULL_PATH}:#{@app.allocating_lines[1]}  allocated    4 `Array<String>`\n",
      "#{HelloWorldApp::FULL_PATH}:#{@app.allocating_lines[1]}  allocated    4 `Array<Fixnum,Hash,Array>`\n",
      "#{HelloWorldApp::FULL_PATH}:#{@app.allocating_lines[1]}  allocated    4 `Hash`\n",
      "#{HelloWorldApp::FULL_PATH}:#{@app.allocating_lines[0]}  allocated    4 `String`\n"
    ]

    expect(body).to include(expected_body[0])
    expect(body).to include(expected_body[1])
    expect(body).to include(expected_body[2])
    expect(body).to include(expected_body[3])
    expect(body).to include(expected_body[4])
  end

  it "returns correct body when called on just local files" do
    yaml_app = YamlApp.new
    request_env  = Rack::MockRequest.env_for("/", :params => "ras[trace]=true&ras[scope]=.")
    _, _, body = Rack::AllocationStats.new(yaml_app).call(request_env)

    # body should be:
    # yaml_app.rb:17  allocated    2 `String`
    # yaml_app.rb:18  allocated    2 `String`
    # yaml_app.rb:18  allocated    1 `Array<String>`
    # yaml_app.rb:18  allocated    1 `Array<Fixnum,Hash,Array>`
    # yaml_app.rb:17  allocated    1 `Array<String>`
    # yaml_app.rb:18  allocated    1 `Hash`

    expect(body.size).to eq 6
  end

  it "returns the correct body when called on a specific directory" do
    yaml_app = YamlApp.new
    psych_request_env  = Rack::MockRequest.env_for("/", :params => "ras[trace]=true&ras[scope]=psych")
    _, _, body = Rack::AllocationStats.new(yaml_app).call(psych_request_env)

    expect(body.size).to eq 42
  end

  it "returns HTML5 in response to an interactive request" do
    interactive_request_env  = Rack::MockRequest.env_for("/", :params => "ras[trace]=true&ras[output]=interactive")
    _, _, body = Rack::AllocationStats.new(@app).call(interactive_request_env)

    expect(body[0]).to match /^<!DOCTYPE html>/
  end

  it "returns the corrent Content-Length in the headers" do
    file = "/foo/bar.rb"
    line = 7

    # TODO 5 comes from factories.rb; it should come from here.
    # TODO String comes from factories.rb; it should come from here.
    expected_body = "#{file}:#{line}   allocated    5 `String`\n"

    stats = FactoryGirl.build(:stats, files: [file], sourceline: line)
    AllocationStats.stub(:trace) { stats }
    allocation_stats = Rack::AllocationStats.new(@app)
    _, headers, _ = allocation_stats.call(@traced_request_env)

    headers["Content-Length"].to_i.should be expected_body.length
  end

  context("scoping") do
    before do
      stats = FactoryGirl.build(:stats, files: ["/foo/bar.rb", File.join(Dir.pwd, "baz.rb")])
      AllocationStats.stub(:trace) { stats }
      @allocation_stats = Rack::AllocationStats.new(@app)
    end

    it "returns all allocations when no scope is specified" do
      _, _, body = @allocation_stats.call(@traced_request_env)

      text = body.join
      text.should include("bar.rb")
      text.should include("baz.rb")
    end

    it "returns locally-scoped allocations" do
      request_env  = Rack::MockRequest.env_for("/", :params => "ras[trace]=true&ras[scope]=.")

      _, _, body = @allocation_stats.call(request_env)

      text = body.join
      text.should include("baz.rb")
      text.should_not include("bar.rb")
    end

    it "returns allocations limited by scope" do
      request_env  = Rack::MockRequest.env_for("/", :params => "ras[trace]=true&ras[scope]=foo")

      _, _, body = @allocation_stats.call(request_env)

      text = body.join
      text.should include("bar.rb")
      text.should_not include("baz.rb")
    end
  end

  it "returns JSON when res[output]=json" do
    stats = FactoryGirl.build(:stats, files: ["/foo/bar.rb", File.join(Dir.pwd, "baz.rb")])
    AllocationStats.stub(:trace) { stats }
    @allocation_stats = Rack::AllocationStats.new(@app)

    json_request_env  = Rack::MockRequest.env_for("/", :params => "ras[trace]=true&ras[output]=json")
    _, _, body = @allocation_stats.call(json_request_env)

    allocation = stats.allocations.all.first
    first_group_key = ["/foo/bar.rb", 7, String]

    text = body.join
    text.should include(allocation.to_json)
    text.should include(first_group_key.to_json)

    hash = {group_key: first_group_key, allocations: [allocation, allocation, allocation]}

    text.should include(Yajl::Encoder.encode(hash))
  end

  it "returns the right Content-Type and status for JSON" do
    json_request_env  = Rack::MockRequest.env_for("/", :params => "ras[trace]=true&ras[output]=json")
    status, headers, _ = Rack::AllocationStats.new(@app).call(json_request_env)

    expect(headers["Content-Type"]).to eq "application/json"
    expect(status).to be 200
  end

  it "returns the right Content-Type and status for help" do
    help_request_env  = Rack::MockRequest.env_for("/", :params => "ras[help]")
    status, headers, _ = Rack::AllocationStats.new(@app).call(help_request_env)

    expect(headers["Content-Type"]).to eq "text/plain"
    expect(status).to be 200
  end

  it "returns the right body for help" do
    help_request_env  = Rack::MockRequest.env_for("/", :params => "ras[help]")
    _, _, body = Rack::AllocationStats.new(@app).call(help_request_env)

    body.first.should include("Rack AllocationStats help\n")
  end
end
