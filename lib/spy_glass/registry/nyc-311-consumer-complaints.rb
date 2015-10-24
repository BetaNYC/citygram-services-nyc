require 'spy_glass/registry'

query = {
  '$limit' => 1000,
  '$order' => 'created_date DESC',
  '$where' => <<-WHERE.oneline
    created_date >= '#{SpyGlass::Utils.last_week_floating_timestamp}' AND
    longitude IS NOT NULL AND
    latitude IS NOT NULL AND
    (
      complaint_type = 'Consumer Complaint' OR
      complaint_type = 'For Hire Vehicle Complaint'
    ) AND
    unique_key IS NOT NULL
  WHERE
}

opts = {
  path: '/nyc-311-consumer-complaints',
  cache: SpyGlass::Cache::Memory.new(expires_in: 300),
  source: 'https://data.cityofnewyork.us/resource/fhrw-4uyv.json?'+ Rack::Utils.build_query(query)
}

time_zone = ActiveSupport::TimeZone['Eastern Time (US & Canada)']
SpyGlass::Registry << SpyGlass::Client::Socrata.new(opts) do |collection|
  features = collection.map do |item|
    time = Time.iso8601(item['created_date']).in_time_zone(time_zone).strftime("%m/%d  %I:%M %p")

    title =
      case item['address_type']
      when 'ADDRESS'
        "#{time} | #{item['descriptor']} at #{item['incident_address'].titleize}."
      when 'INTERSECTION'
        "#{time} | #{item['descriptor']} at #{item['intersection_street_1'].titleize} and #{item['intersection_street_2'].titleize}."
      when 'BLOCKFACE'
        "#{time} | #{item['descriptor']} on #{item['street_name'].titleize}, between #{item['cross_street_2'].titleize} and #{item['cross_street_1'].titleize}."
      else
        "#{time} | #{item['descriptor']} on #{item['street_name']}."
      end
    title << " #{item['agency']}, #{item['complaint_type']}."

    {
      'id' => item['unique_key'],
      'type' => 'Feature',
      'geometry' => {
        'type' => 'Point',
        'coordinates' => [
          item['longitude'].to_f,
          item['latitude'].to_f
        ]
      },
      'properties' => item.merge('title' => title)
    }
  end

  {
    'type' => 'FeatureCollection',
    'features' => features
  }
end
