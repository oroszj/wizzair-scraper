#!/usr/bin/env ruby
#
# Copyright Jozsef Orosz jozsef@orosz.name
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

require 'pp'
require "./wizzair_api.rb"
require "yaml/store"
require "pony"


# Load required flights where we search for input
store = YAML::Store.new "data.yml"
watches = []
email = {}

# One liner lambda to convert hash keys to symbols from strings for email
symbolize = lambda { |h| h.is_a?(Hash) ? Hash[h.map { |k,v| [ k.to_sym, symbolize[v] ]}] : h }

store.transaction(true) do
  # Read data
  watches = store['watch']
  email = symbolize[store['email']]
  email[:body] = "" unless email.nil?
end

abort "Nothing to do?! Do you have 'watch' entries in data.yml?" if watches.nil?

scraper = WizzAPI.new
watches.each_with_index do |watch, index|
  if watch['from'].nil? || watch['to'].nil? || watch['date'].nil?
    puts "["+index.to_s+"] is an invalid entry, skipping"
    next
  end
  
  best_price_orig = best_price = watch.fetch 'best_fare',Float::INFINITY
  puts "["+index.to_s+"] searching "+watch['from']+" > "+watch['to']+" on "+watch['date'].to_s+" best price @ "+best_price.to_s
  
  res = scraper.search watch['from'],watch['to'],watch['date']
  res.each do |f|
    if f[:best_fare] < best_price && 
      ( f[:flight_code] == watch['flight'] || watch['flight'].nil? ) then
        best_price = f[:best_fare]
        puts "Found a better price on "+f[:flight_code]+" for "+best_price.to_s
    end
  end
  
  if best_price < best_price_orig then
    # Save new value
    store.transaction { store['watch'][index]['best_fare'] = best_price }
    email[:body] << "Better fare for "+watch['from']+" > "+watch['to']+" on "+watch['date'].to_s+" best price is now "+best_price.to_s+" from "+best_price_orig.to_s+"\n"
  end
  
end

# Finally send email if we have a body and someone to send to
Pony.mail(email) if not (email.nil? || email[:body].empty? || email[:to].nil? )