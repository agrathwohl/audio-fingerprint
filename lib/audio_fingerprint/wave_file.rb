###############################################################################
### This class was took from the wavefile gem version 0.3.0 to fit my needs ###
### https://github.com/jstrait/wavefile #######################################
###############################################################################

module AudioFingerprint
    class WaveFile
        CHUNK_ID = "RIFF"
        FORMAT = "WAVE"
        FORMAT_CHUNK_ID = "fmt "
        SUB_CHUNK1_SIZE = 16
        PCM = 1
        DATA_CHUNK_ID = "data"
        HEADER_SIZE = 36

        def initialize(num_channels, sample_rate, bits_per_sample, sample_data = [])
            if num_channels == :mono
                @num_channels = 1
            elsif num_channels == :stereo
                @num_channels = 2
            else
                @num_channels = num_channels
            end
            @sample_rate = sample_rate
            @bits_per_sample = bits_per_sample
            @sample_data = sample_data

            @byte_rate = sample_rate * @num_channels * (bits_per_sample / 8)
            @block_align = @num_channels * (bits_per_sample / 8)
        end
      
        def self.open(path)
            file = File.open(path, "rb")

            begin
                header = read_header(file)
                errors = validate_header(header)

                if errors == []
                    sample_data = read_sample_data(file,
                    header[:num_channels],
                    header[:bits_per_sample],
                    header[:sub_chunk2_size])

                    wave_file = self.new(header[:num_channels],
                    header[:sample_rate],
                    header[:bits_per_sample],
                    sample_data)
                else
                    error_msg = "#{path} can't be opened, due to the following errors:\n"
                    errors.each {|error| error_msg += "  * #{error}\n" }
                    raise StandardError, error_msg
                end
            rescue EOFError
                raise StandardError, "An error occured while reading #{path}."
            ensure
                file.close()
            end

            return wave_file
        end

        def save(path)
            # All numeric values should be saved in little-endian format

            sample_data_size = @sample_data.length * @num_channels * (@bits_per_sample / 8)

            # Write the header
            file_contents = CHUNK_ID
            file_contents += [HEADER_SIZE + sample_data_size].pack("V")
            file_contents += FORMAT
            file_contents += FORMAT_CHUNK_ID
            file_contents += [SUB_CHUNK1_SIZE].pack("V")
            file_contents += [PCM].pack("v")
            file_contents += [@num_channels].pack("v")
            file_contents += [@sample_rate].pack("V")
            file_contents += [@byte_rate].pack("V")
            file_contents += [@block_align].pack("v")
            file_contents += [@bits_per_sample].pack("v")
            file_contents += DATA_CHUNK_ID
            file_contents += [sample_data_size].pack("V")

            # Write the sample data
            if !mono?
                output_sample_data = []
                @sample_data.each{|sample|
                    sample.each{|sub_sample|
                        output_sample_data << sub_sample
                    }
                }
            else
                output_sample_data = @sample_data
            end

            if @bits_per_sample == 8
                file_contents += output_sample_data.pack("C*")
            elsif @bits_per_sample == 16
                file_contents += output_sample_data.pack("s*")
            else
                raise StandardError, "Bits per sample is #{@bits_per_samples}, only 8 or 16 are supported"
            end

            file = File.open(path, "w")
            file.syswrite(file_contents)
            file.close
        end

        def sample_data()
            return @sample_data
        end

        def normalized_sample_data()    
            if @bits_per_sample == 8
                min_value = 128.0
                max_value = 127.0
                midpoint = 128
            elsif @bits_per_sample == 16
                min_value = 32768.0
                max_value = 32767.0
                midpoint = 0
            else
                raise StandardError, "Bits per sample is #{@bits_per_samples}, only 8 or 16 are supported"
            end

            if mono?
                normalized_sample_data = @sample_data.map {|sample|
                    sample -= midpoint
                    if sample < 0
                        sample.to_f / min_value
                    else
                        sample.to_f / max_value
                    end
                }
            else
                normalized_sample_data = @sample_data.map {|sample|
                    sample.map {|sub_sample|
                        sub_sample -= midpoint
                        if sub_sample < 0
                            sub_sample.to_f / min_value
                        else
                            sub_sample.to_f / max_value
                        end
                    }
                }
            end

            return normalized_sample_data
        end
      
        def sample_data=(sample_data)
            if sample_data.length > 0 && ((mono? && sample_data[0].class == Float) ||
                                        (!mono? && sample_data[0][0].class == Float))
            if @bits_per_sample == 8
                # Samples in 8-bit wave files are stored as a unsigned byte
                # Effective values are 0 to 255, midpoint at 128
                min_value = 128.0
                max_value = 127.0
                midpoint = 128
            elsif @bits_per_sample == 16
                # Samples in 16-bit wave files are stored as a signed little-endian short
                # Effective values are -32768 to 32767, midpoint at 0
                min_value = 32768.0
                max_value = 32767.0
                midpoint = 0
            else
                raise StandardError, "Bits per sample is #{@bits_per_samples}, only 8 or 16 are supported"
            end

            if mono?
                @sample_data = sample_data.map {|sample|
                    if(sample < 0.0)
                    (sample * min_value).round + midpoint
                    else
                    (sample * max_value).round + midpoint
                    end
                }
            else
                @sample_data = sample_data.map {|sample|
                    sample.map {|sub_sample|
                        if(sub_sample < 0.0)
                            (sub_sample * min_value).round + midpoint
                        else
                            (sub_sample * max_value).round + midpoint
                        end
                    }
                }
            end
            else
                @sample_data = sample_data
            end
        end

        def mono?()
            return num_channels == 1
        end

        def stereo?()
            return num_channels == 2
        end

        def reverse()
            sample_data.reverse!()
        end

        def duration()
            total_samples = sample_data.length
            samples_per_millisecond = @sample_rate / 1000.0
            samples_per_second = @sample_rate
            samples_per_minute = samples_per_second * 60
            samples_per_hour = samples_per_minute * 60
            hours, minutes, seconds, milliseconds = 0, 0, 0, 0

            if(total_samples >= samples_per_hour)
                hours = total_samples / samples_per_hour
                total_samples -= samples_per_hour * hours
            end

            if(total_samples >= samples_per_minute)
                minutes = total_samples / samples_per_minute
                total_samples -= samples_per_minute * minutes
            end

            if(total_samples >= samples_per_second)
                seconds = total_samples / samples_per_second
                total_samples -= samples_per_second * seconds
            end

            milliseconds = (total_samples / samples_per_millisecond).floor

            return  { :hours => hours, :minutes => minutes, :seconds => seconds, :milliseconds => milliseconds }
        end

        def bits_per_sample=(new_bits_per_sample)
            if new_bits_per_sample != 8 && new_bits_per_sample != 16
                raise StandardError, "Bits per sample of #{@bits_per_samples} is invalid, only 8 or 16 are supported"
            end

            if @bits_per_sample == 16 && new_bits_per_sample == 8
                conversion_func = lambda {|sample|
                    if(sample < 0)
                        (sample / 256) + 128
                    else
                        # Faster to just divide by integer 258?
                        (sample / 258.007874015748031).round + 128
                    end
                }

                if mono?
                    @sample_data.map! &conversion_func
                else
                    sample_data.map! {|sample| sample.map! &conversion_func }
                end
                elsif @bits_per_sample == 8 && new_bits_per_sample == 16
                    conversion_func = lambda {|sample|
                        sample -= 128
                        if(sample < 0)
                            sample * 256
                        else
                            # Faster to just multiply by integer 258?
                            (sample * 258.007874015748031).round
                        end
                    }

                if mono?
                    @sample_data.map! &conversion_func
                else
                    sample_data.map! {|sample| sample.map! &conversion_func }
                end
            end

            @bits_per_sample = new_bits_per_sample
        end
      
        def num_channels=(new_num_channels)
            if new_num_channels == :mono
                new_num_channels = 1
            elsif new_num_channels == :stereo
                new_num_channels = 2
            end

            # The cases of mono -> stereo and vice-versa are handled in specially,
            # because those conversion methods are faster than the general methods,
            # and the large majority of wave files are expected to be either mono or stereo.    
            if @num_channels == 1 && new_num_channels == 2
                sample_data.map! {|sample| [sample, sample]}
            elsif @num_channels == 2 && new_num_channels == 1
                sample_data.map! {|sample| (sample[0] + sample[1]) / 2}
            elsif @num_channels == 1 && new_num_channels >= 2
                sample_data.map! {|sample| [].fill(sample, 0, new_num_channels)}
            elsif @num_channels >= 2 && new_num_channels == 1
                sample_data.map! {|sample| sample.inject(0) {|sub_sample, sum| sum + sub_sample } / @num_channels }
            elsif @num_channels > 2 && new_num_channels == 2
                sample_data.map! {|sample| [sample[0], sample[1]]}
            end

            @num_channels = new_num_channels
        end

        def inspect()
            duration = self.duration()

            result =  "Channels:        #{@num_channels}\n" +
                        "Sample rate:     #{@sample_rate}\n" +
                        "Bits per sample: #{@bits_per_sample}\n" +
                        "Block align:     #{@block_align}\n" +
                        "Byte rate:       #{@byte_rate}\n" +
                        "Sample count:    #{@sample_data.length}\n" +
                        "Duration:        #{duration[:hours]}h:#{duration[:minutes]}m:#{duration[:seconds]}s:#{duration[:milliseconds]}ms\n"
        end

        attr_reader :num_channels, :bits_per_sample, :byte_rate, :block_align
        attr_accessor :sample_rate
      
    private

        def self.read_header(file)
            header = {}

            # Read RIFF header
            riff_header = file.sysread(12).unpack("a4Va4")
            header[:chunk_id] = riff_header[0]
            header[:chunk_size] = riff_header[1]
            header[:format] = riff_header[2]

            # Read format subchunk
            header[:sub_chunk1_id], header[:sub_chunk1_size] = self.read_to_chunk(file, FORMAT_CHUNK_ID)
            format_subchunk_str = file.sysread(header[:sub_chunk1_size])
            format_subchunk = format_subchunk_str.unpack("vvVVvv")  # Any extra parameters are ignored
            header[:audio_format] = format_subchunk[0]
            header[:num_channels] = format_subchunk[1]
            header[:sample_rate] = format_subchunk[2]
            header[:byte_rate] = format_subchunk[3]
            header[:block_align] = format_subchunk[4]
            header[:bits_per_sample] = format_subchunk[5]

            # Read data subchunk
            header[:sub_chunk2_id], header[:sub_chunk2_size] = self.read_to_chunk(file, DATA_CHUNK_ID)

            return header
        end

        def self.read_to_chunk(file, expected_chunk_id)
            chunk_id = file.sysread(4)
            chunk_size = file.sysread(4).unpack("V")[0]

            while chunk_id != expected_chunk_id
                # Skip chunk
                file.sysread(chunk_size)

                chunk_id = file.sysread(4)
                chunk_size = file.sysread(4).unpack("V")[0]
            end

            return chunk_id, chunk_size
        end

        def self.validate_header(header)
            errors = []

            unless header[:bits_per_sample] == 8  ||  header[:bits_per_sample] == 16
                errors << "Invalid bits per sample of #{header[:bits_per_sample]}. Only 8 and 16 are supported."
            end

            unless (1..65535) === header[:num_channels]
                errors << "Invalid number of channels. Must be between 1 and 65535."
            end

            unless header[:chunk_id] == CHUNK_ID
                errors << "Unsupported chunk ID: '#{header[:chunk_id]}'"
            end

            unless header[:format] == FORMAT
                errors << "Unsupported format: '#{header[:format]}'"
            end

            unless header[:sub_chunk1_id] == FORMAT_CHUNK_ID
                errors << "Unsupported chunk id: '#{header[:sub_chunk1_id]}'"
            end

            unless header[:audio_format] == PCM
                errors << "Unsupported audio format code: '#{header[:audio_format]}'"
            end

            unless header[:sub_chunk2_id] == DATA_CHUNK_ID
                errors << "Unsupported chunk id: '#{header[:sub_chunk2_id]}'"
            end

            return errors
        end
      
        # Assumes that file is "queued up" to the first sample
        def self.read_sample_data(file, num_channels, bits_per_sample, sample_data_size)
            if(bits_per_sample == 8)
                data = file.sysread(sample_data_size).unpack("C*")
            elsif(bits_per_sample == 16)
                data = file.sysread(sample_data_size).unpack("s*")
            else
                data = []
            end

            if(num_channels > 1)
                multichannel_data = []

                i = 0
                while i < data.length
                    multichannel_data << data[i...(num_channels + i)]
                    i += num_channels
                end

                data = multichannel_data
            end

            return data
        end
    end
end