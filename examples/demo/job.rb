require 'resque'

module Demo
  module Job
    @queue = :default

    def self.perform(params)
      puts params
      sleep 1
      puts "Processed a job!"
    end
  end

  module FailingJob
    #define queue name
    @queue = :failing

    def self.perform(params)
      sleep 1
      raise 'not processable!'
      puts "Processed a job!"
    end
  end
end
