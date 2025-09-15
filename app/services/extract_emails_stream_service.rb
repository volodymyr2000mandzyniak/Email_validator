# app/services/extract_emails_stream_service.rb
class ExtractEmailsStreamService
  LOOSE_EMAIL_RE = /
    [^\s<>"'()\[\]\\,;:]+
    @
    [^\s<>"'()\[\]\\,;:]+
  /x

  CHUNK = 1024 * 256  # 256KB  ← було 64KB

  def self.call(path)
    raise ArgumentError, "no block given" unless block_given?
    File.open(path, 'rb') do |io|
      buffer = +""
      while (chunk = io.read(CHUNK))
        buffer << chunk
        tail = buffer[-256..] || buffer
        buffer.scan(LOOSE_EMAIL_RE) { |m| yield m }
        buffer = tail
      end
      buffer.scan(LOOSE_EMAIL_RE) { |m| yield m }
    end
  end
end
