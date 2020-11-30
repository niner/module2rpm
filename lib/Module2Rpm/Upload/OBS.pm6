use XML;

use Module2Rpm::Role::Internet;
use Module2Rpm::Package;

=begin pod

=head1 Module2Rpm::Upload::OBS

=head2 More Infos
    L<https://build.opensuse.org/apidocs/index>

=end pod

class Module2Rpm::Upload::OBS {
    has Module2Rpm::Role::Internet $.client is required;
    has $.project is required;
    has Set $.packages;
    has $.api-url = 'https://api.opensuse.org';

    method package-exists(Str $package-name --> Bool) {
        self.get-packages();
        return $!packages{$package-name};
    }

    method create-package(Module2Rpm::Package :$package) {
        # Have to filter the description otherwise special characters like $ will break
        # the api.opensuse.org verifying check:
        # <status code="validation_failed">
        #  <summary>package validation error: 3:36: FATAL: xmlParseEntityRef: no name</summary>
        #</status>
        my $description = $package.spec.get-summary();
        $description ~~ s:g/<-[\s \w]>+//;

        my $xml = qq:to/END/;
        <package name="{$package.module-name}" project="$!project">
            <title>{$package.module-name}</title>
            <description>{$description}</description>
        </package>
        END
        my $url = $!api-url ~ "/source/" ~ $!project  ~ "/" ~ $package.module-name ~ "/_meta";
        $!client.put($url, content-type => "application/xml", body => $xml);
    }

    method delete-package(Module2Rpm::Package :$package!) {
        my $url = $!api-url ~ "/source/" ~ $!project ~ "/" ~ $package.module-name;
        $!client.delete($url);
    }

    method delete-all-packages() {
        self.get-packages();
        for $!packages.keys -> $package {
            say "Delete $package";
            my $url = $!api-url ~ "/source/" ~ $!project ~ "/" ~ $package;
            $!client.delete($url);
        }
    }

    method upload-files(Module2Rpm::Package :$package!) {
        if not self.package-exists($package.module-name) {
            say "Create package {$package.module-name}";
            self.create-package(:$package);
        }

        my $url-source-archive = $!api-url ~ "/source/" ~ $!project ~ "/" ~ $package.module-name ~ "/" ~ $package.tar-name;
        my $url-spec-file = $!api-url ~ "/source/" ~ $!project ~ "/" ~ $package.module-name ~ "/" ~ $package.spec-file-name;

        my $tar-archive-binary-content = $package.tar-archive-path.slurp(:bin, :close);
        my $spec-file-content = $package.spec-file-path.slurp(:close);

        say "{$package.module-name}: Upload tar archive file";
        $!client.put($url-source-archive, content-type => "application/octet-stream", body => $tar-archive-binary-content);
        say "{$package.module-name}: Upload spec file";
        $!client.put($url-spec-file, body => $spec-file-content);
    }

    method get($url = "" --> XML::Document) {
        my $body = $!client.get($url);

        if $body ~~ Buf {
            my $str = $body.decode;
            return from-xml($str);
        }

        if $body ~~ Str {
            return from-xml($body);
        }

        die "Unknown type received: {$body.WHAT}";
    }

    method get-packages() {
        return $!packages if $!packages.defined;

        my $xml = self.get($!api-url ~ "/source/" ~ $!project);
        my @packages;
        for $xml.root -> $note {
            for $note.elements -> $element {
                @packages.push: $element.attribs<name>;
            }
        }

        $!packages = Set.new(@packages);
    }
}
