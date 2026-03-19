# frozen_string_literal: true

require 'prometheus/client'
require 'prometheus/client/formats/text'

# Initialize Prometheus registry with default metrics
Prometheus::Client.registry
