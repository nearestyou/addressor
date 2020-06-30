load 'lib/addressor_utils.rb'
load 'lib/constants.rb'
load 'lib/extensions.rb'

class NYIdentifier
attr_accessor :str, :sep, :sep_map, :locale, :bus

def initialize(nya = nil)
  @bus = {}
  if @nya = nya
    # clean_string
  end
  self
end

def identifications
  identify
  { sep: @sep, sep_map: @sep_map, sep_comma: @sep_comma, locale: @locale, bus: @bus, parts: @parts }
end

def identify
  create_sep_comma
  remove_extraneous
  separate
  remove_duplicates
  create_sep_map
  identify_all_by_pattern
  identify_all_by_location
  consolidate_identity_options
  strip_identity_options
  check_po
  standardize_aliases
  select_final_options
end

def create_sep_map
  @sep_map = @sep.map{|part| {text: part, down: part.gsub('.','').downcase, typified: AddressorUtils.typify(part)} }
end

def create_sep_comma
  @sep_comma = []
  @nya.orig.split(',').each do |section|
    words = section.split(' ')
    @sep_comma.push words
  end
end

def separate
  @sep = @str.split(' ')
  @sep_map = @sep.map{|i| {}}
end

def remove_duplicates
  @sep = @sep.uniq
  @sep = @sep.map(&:downcase)

  #Looking for different ways of saying usa
  og = @nya.orig.downcase
  alias_index = []
  start_index = []
  NYAConstants::US_ALIAS.each do |name|
    if og.include? name
      start = og.index(name)
      if not start_index.include? start
        start_index.push(start)
        alias_index.push([start, name.length])
      end
    end
  end
  while alias_index.length > 1
    abrev = og[alias_index[0][0], alias_index[0][1]]
    abrev = abrev.split(' ')
    abrev.each do |word|
      @sep.delete(word)
    end
    alias_index.delete_at(0)
  end
end

def identify_all_by_pattern
  @sep_map.each_with_index do |part, i|
    @sep_map[i][:from_pattern] = pattern_options(part)
  end
end

def remove_extraneous
  @bus = {}
  ## Remove street corners
  @sep_comma.each do |sep|
    if sep.map(&:downcase).include? 'corner' or sep.map(&:downcase).include? 'coner'
      @sep_comma.delete(sep)
      @bus[:corner] = sep.join(" ")
    end
  end
  ## Update @str
  @str = ""
  @sep_comma.each do |sep|
    sep.each do |part|
      @str += part + ' '
    end
  end
  @str = @str.chop
  @str = @str.gsub('.', '')

  ## Remove parentheses
  while @str.include?('(') and @str.include?(')')
    first_open = @str.index('(')
    first_close = @str.index(')')
    @bus[:parentheses] ||= []
    @bus[:parentheses] << @str[first_open+1..first_close-1]
    @str = @str[0..first_open-1] + @str[first_close+1..-1]
  end

  ##Remove punctuation
  @str = @str.gsub(',', '')
  @str = @str.gsub('.', '')
end

def pattern_options(part)
  opts = []
  opts << :street_number if potential_street_number(part)
  opts << :street_name if potential_street_name(part)
  opts << :street_label if potential_street_label(part)
  opts << :street_direction if potential_street_direction(part)
  opts << :unit if potential_unit(part)
  opts << :city if potential_city(part)
  opts << :state if potential_state(part)
  opts << :postal_code if potential_postal_code(part)
  opts << :country if potential_country(part)
  opts
end

def potential_street_number(part)
  return true if some_numbers(part)
  return true if %w[box po].include?(part[:down])
end

def potential_street_name(part)
  true
end

def potential_street_label(part)
  %w[avenue ave boulevard blvd circle cir court ct drive dr expressway expy highway hwy lane ln parkway pkwy place pl plaza plz road rd route rt square sq street st terrace tr trail trl way wy].include?(part[:down])
end

def potential_street_direction(part)
  %w[e n s w east north south west no so ne nw se sw northeast northwest southeast southwest].include?(part[:down])
end

def potential_unit(part)
  return true if part[:down].start_with?('#')
  return true if part[:down].start_with?('apt')
  return true if part[:down].start_with?('ste')
  return true if part[:down].start_with?('suite')
  return true if part[:down].numeric?
  return false
end

def potential_city(part)
  letters_only(part)
end

def potential_state(part)
  return true if NYAConstants::STATE_DESCRIPTORS.include?(part[:down])
  # return true if letters_only(part) and part[:down].length < 5
  return false
end

def potential_postal_code(part)
  case part[:typified]
  when '|||||'
    true
  when '|||||-||||'
    true
  when '|||||||||'
    true
  when '=|= |=|'
    true
  when '=|='
    true
  when '|=|'
    true
  else
    false
  end
end

def potential_country(part)
  letters_only(part)
end

def identify_all_by_location
  nParts = @sep.length
  @sep_map.each_with_index do |part, i|
    @sep_map[i][:from_location] = location_options(part, i, nParts)
  end
end

def location_options(part, i, nParts)
  case i
  when 0
    [:street_number, :street_name]
  when 1
    [:street_number, :street_name, :street_direction]
  when 2
    [:street_name, :street_label, :street_unit, :street_direction]
  when nParts - 3
    [:city, :state, :postal_code]
  when nParts - 2
    [:state, :postal_code]
  when nParts - 1
    [:state, :postal_code, :country]
  else
    [:street_name, :street_label, :street_direction, :unit, :city, :state]
  end
end

def consolidate_identity_options
  @sep_map.each do |part|
    part[:in_both] = part[:from_location] & part[:from_pattern]
  end
end

def strip_identity_options
  @sep_map.each do |sep|
    sep[:stripped] = sep[:in_both]
  end
  strip_state_options
  strip_street_number_options
  strip_street_name_options
  strip_direction_options
  strip_street_label_options
  strip_city_options
end

def strip_state_options
  found = false
  @sep_map.reverse.each do |sep|
    if sep[:stripped].include? :state and found
      sep[:stripped].delete(:state)
    elsif sep[:stripped].include? :state
      found = true
      sep[:stripped] = [:state]
    end
  end
  #Check for compound state
  if not found
    @sep_map.reverse.each_with_index do |sep, i|
      if i+1 < @sep_map.length
        if NYAConstants::STATE_DESCRIPTORS.include?("#{sep_map.reverse[i+1][:down]} #{sep[:down]}")
          sep_map.reverse[i+1][:stripped] = [:state]
          sep_map.reverse[i][:stripped] = [:state]
        end
      end
    end
  end
end

def strip_street_number_options
  first_sep = @sep_map[0]
  if first_sep[:text].length == 4 and first_sep[:text].numeric?
    first_sep[:stripped] = [:street_number]
  end
end

def strip_street_name_options
  #Find start and stop points
  name_start_index = 0
  name_stop_index = 0
  @sep_map.each_with_index do |sep, i|
    if @sep_map.length > i+1
      if name_start_index != 0 and name_stop_index == 0 and (sep[:stripped].include? :street_label or sep[:stripped].include? :street_direction or sep[:stripped].include? :city)
        name_stop_index = i-1
      elsif (sep[:stripped].include? :street_number or sep[:stripped].include? :street_direction) and name_start_index == 0 and not @sep_map[i+1][:stripped].include? :street_direction
        name_start_index = i+1
      end
    end
  end
  #eliminate options
  @sep_map.each_with_index do |sep, i|
    if i >= name_start_index and i <= name_stop_index
      sep[:stripped] = [:street_name]
    elsif sep[:stripped].include? :street_name
      sep[:stripped].delete :street_name
    end
  end
end

def strip_direction_options
  @sep_map.each_with_index do |sep, i|
    if sep[:stripped].include? :street_direction and @sep_map[i+1][:stripped].include? :city and not sep[:stripped].include? :city
      sep[:stripped] = [:street_direction]
      break
    end
  end
end

def strip_street_label_options
  found = false
  @sep_map.each_with_index do |sep, i|
    if found and sep[:stripped].include? :street_label
      sep[:stripped].delete :street_label
    elsif sep[:stripped].include? :street_label and @sep_map[i-1][:stripped].include? :street_name
      sep[:stripped] = [:street_label]
      found = true
    end
  end
end

def strip_city_options
  found_state = false
  @sep_map.reverse.each_with_index do |sep, i|
    if sep[:stripped] == [:street_label] or sep[:stripped] == [:street_direction]
      break
    elsif not sep[:stripped].include? :city and found_state and not sep[:stripped].include? :state and not sep[:text].numeric?
      sep[:stripped].push(:city)
    elsif sep[:stripped].include? :city and sep[:stripped] != [:city] and @sep_comma.length > 1
      if @sep_comma[1].include? sep[:text]
        sep[:stripped] = [:city]
      else
        sep[:stripped].delete :city
      end
    elsif sep[:stripped].include? :state
      found_state = true
    end
  end
end

def check_po
  po_box = false
  @sep_map.each do |sep|
    if NYAConstants::POBOX_ALIAS.include? sep[:down]
      po_box = true
      break
    end
  end

  if po_box
    @sep_map[0][:stripped] = [:street_name]
    @sep_map[1][:stripped] = [:street_name]
    @sep_map[2][:stripped] = [:street_number]
    if @sep_map[3][:down].numeric?
      @sep_map[3][:stripped] = [:street_number]
    end
  end
end

def select_final_options
  @parts = {}
  @sep_map.each do |sep|
    label = sep[:stripped].first
    part = sep[:text]
    if @parts[label].nil?
      @parts[label] = part
    else
      if label == :street_direction
        @parts[label] = "#{@parts[label]}#{part}"
      else
        @parts[label] = "#{@parts[label]} #{part}"
      end
    end
  end
  @parts[:orig] = @nya.orig
  if @parts.size() < 4
    @parts = nil
  end
end

def standardize_aliases
  @sep_map.each do |sep|
    if sep[:stripped].include? :street_number and sep[:text].include? '-' or sep[:text].include? '/'
      sep[:text] = sep[:text].reverse()[0,5].reverse()
    elsif sep[:stripped].include? :street_name and NYAConstants::NUMBER_STREET.keys.include? sep[:down]
      sep[:text] = NYAConstants::NUMBER_STREET[sep[:down]]
    elsif sep[:stripped].include? :street_direction and NYAConstants::STREET_DIRECTIONS.keys.include? sep[:down]
      sep[:text] = NYAConstants::STREET_DIRECTIONS[sep[:down]]
    elsif sep[:stripped].include? :street_label and NYAConstants::STREET_LABELS.keys.include? sep[:text]
      sep[:text] = NYAConstants::STREET_LABELS[sep[:text]]
    elsif sep[:stripped].include? :state and NYAConstants::STATE_KEYS.include? sep[:down]
      sep[:text] = NYAConstants::US_STATES[sep[:down].capitalize()] if NYAConstants::US_STATES[sep[:down].capitalize()]
      sep[:text] = NYAConstants::CA_PROVINCES[sep[:down].capitalize()] if NYAConstants::CA_PROVINCES[sep[:down].capitalize()]
    end
  end
end

def letters_only(part)
  !part[:typified].include?('|')
end

def some_numbers(part)
  part[:typified].include?('|')
end

def set_locale
  @nya.typify
  @locale = if @nya.typified.include?('=|= |=|')
    :ca
  else
    :us
  end
end

end
