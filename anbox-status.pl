#!/usr/bin/env perl

use strict;              # Perl pragma to restrict unsafe constructs
use warnings;            # Perl pragma to control optional warnings
use diagnostics;         # diagnostics, splain - produce verbose warning diagnostics
use feature ':5.14';     # Perl pragma to enable new features
use Gtk3 '-init';
use Glib qw/TRUE FALSE/;
use Time::HiRes qw ( setitimer ITIMER_REAL time );
use HTML::Entities;
 

$AnboxStatus::APP_NAME      = 'Anbox Status & Control';
$AnboxStatus::ICON          = '/snap/anbox/current/snap/gui/icon.png';
$AnboxStatus::CMD_IFCONFIG  = '/sbin/ifconfig';
$AnboxStatus::CMD_SYSTEMCTL = 'systemctl';
$AnboxStatus::CMD_ANBOX     = 'snap run anbox';
$AnboxStatus::SERVICE       = 'snap.anbox.container-manager.service';

# possible locations of desktop files for Android apps
@AnboxStatus::DESKTOPS = (
    $ENV{'HOME'} . '/.local/share/applications/anbox',
    '/usr/share/applications/anbox',
    '/usr/local/share/applications/anbox',
    '/snap/anbox/current/desktop/',
    $ENV{'HOME'} . '/snap/anbox/common/app-data/applications/anbox'
);

# right side function buttons
@AnboxStatus::BUTTONS = (
    {text => 'Anbox session'},
    {text => 'Start Session Manager', exec => sub { 
        exec_launch("$AnboxStatus::CMD_ANBOX session-manager&", "Session Manager");
    }},

    {text => 'Stop Session Manager', exec => sub {
        exec_launch("killall anbox","killall anbox");
    }},
    
    {text => 'Android'},
    {text => 'Anbox Application Manager', exec => sub {
        exec_launch("$AnboxStatus::CMD_ANBOX launch --package=org.anbox.appmgr --component=org.anbox.appmgr.AppViewActivity",
                    "Anbox Application Manager");
    }},

    {text => 'Exchange'},
    {text => 'thunar ftp://', exec => sub {
        if (length($AnboxStatus::ip) > 6) {
            exec_launch("thunar ftp://$AnboxStatus::ip:2121/ &");
        } else {
            exec_launch_error(getTime(), "thunar ftp://[ip is missing]:2121/ &");
        }
    }},

#    {text => 'adb shell', exec => sub {
#        exec_launch("xfce4-terminal -x adb shell &");
#    }},
    
    {text => 'ADB Shell', exec => sub {
        exec_launch("../adb-shell/adb-shell.py l&", "ADB Shell");
    }}


);


my @dom_desktops;

my $ui_window = ui_create_toplevel();

sub ui_create_toplevel {
    my $window = Gtk3::Window->new('toplevel');
    $window->set_title($AnboxStatus::APP_NAME);
    $window->set_border_width(20);
    
    eval {
        my $pixbuf = cl_get_pixbuf($AnboxStatus::ICON, 64);
        $window->set_icon($pixbuf);
    };

    $window->signal_connect (delete_event => \&quit_function);
    return $window;
}

# Buttons

my $ui_buttons = ui_create_buttons();


sub ui_create_buttons {
    my $result = Gtk3::Box->new("vertical", 5);

    $result->set_homogeneous (FALSE);

    foreach(@AnboxStatus::BUTTONS) {
        my %h = %{$_};
        my $text = $h{'text'};
        
        if (exists $h{'exec'}) {
            my $exec = $h{'exec'};
            ui_create_button($result, $text, $exec);
            
        } else {
            $result->add(ui_create_group_label($text));
        }
    }
       
    return $result;
}


sub ui_create_button {
    my ( $parent, $text, $onClicked ) = @_;
    my $result = Gtk3::Button->new($text);

    $result->signal_connect (clicked => $onClicked);
    $parent->add($result);
    return $result;
}




my $ui_list = ui_create_list();
my $ui_list_scroller = ui_scroll($ui_list);


sub ui_create_list {
    my $result = Gtk3::ListBox->new();
    $result->signal_connect (row_activated => \&cl_list_row_activated);
    $result->set_activate_on_single_click(FALSE);
    return $result;
}

sub ui_scroll {
    my ( $child ) = @_;
    my $result = Gtk3::ScrolledWindow->new();
    $result->add($child);
    return $result;
}

my $ui_vbox_main = Gtk3::Box->new("vertical", 5);

my $ui_info_anbox     = add_label_to($ui_vbox_main);
my $ui_info_container = add_label_to($ui_vbox_main);
my $ui_info_session   = add_label_to($ui_vbox_main);
my $ui_info_net       = add_label_to($ui_vbox_main);


my $ui_hbox_main = Gtk3::Box->new("horizontal", 5);

$ui_hbox_main->add($ui_list_scroller);
$ui_hbox_main->set_child_packing($ui_list_scroller, TRUE, TRUE,5, 'start');

$ui_hbox_main->add($ui_buttons);

$ui_vbox_main->add($ui_hbox_main);
$ui_vbox_main->set_child_packing($ui_hbox_main, TRUE, TRUE,5, 'start');


my $ui_info_launch = add_label_to($ui_vbox_main);
$ui_info_launch->set_line_wrap(TRUE);
$ui_info_launch->set_lines(1);

cl_init();
$ui_window->add($ui_vbox_main);
$ui_window->show_all;


sub cl_init {
    read_all_desktop_files();
    cl_fill_list($ui_list);
}

sub cl_get_pixbuf {
    my ( $icon, $size ) = @_;

    my $result = Gtk3::Gdk::Pixbuf->new_from_file_at_size($icon,$size,$size);
    
    return $result;
}


sub cl_get_image {
    my ( $icon, $size ) = @_;
    
    eval {
        my $pixbuf = cl_get_pixbuf($icon, $size);
        return Gtk3::Image->new_from_pixbuf($pixbuf);
    } or do {
        
        return Gtk3::Image->new();
    }
}

sub cl_fill_list {
    my ( $list ) = @_;

    foreach (@dom_desktops) {
        my $entry = Gtk3::Box->new("horizontal", 2);

        my %desktop = %{$_};

        my $image = cl_get_image($desktop{'Icon'},32);
        my $label = Gtk3::Label->new();
        $label->set_xalign(0.0);
        $label->set_text($desktop{'Name'});

        $entry->add($image);
        $entry->add($label);
        $list->insert($entry, -1);
    }
}


sub cl_list_row_activated {
    my ( $box, $row ) = @_;
    my $index = $row->get_index();
    my %desktop = %{$dom_desktops[$index]};
    exec_launch($desktop{'Exec'}, $desktop{'Name'});
}


sub ui_create_group_label {
    my ( $text ) = @_;
    
    my $result = Gtk3::Label->new();
    $result->set_markup(span_bold($text).":");
    #$result->set_xalign(0);
    return $result;
}

sub add_label_to {
    my $parent = $_[0];
    my $result = Gtk3::Label->new();
    $result->set_xalign(0.0);
    $result->set_selectable(TRUE);
    $parent->add($result);

    return $result;
}



$SIG{ALRM} = sub {cl_show_status()};
setitimer(ITIMER_REAL, 0.1, 5);



#### DOMAIN

sub quit_function {
	say "quit";
	Gtk3->main_quit;
	return FALSE;
}


$AnboxStatus::ip = "";




sub cl_show_status {

    my $check = exec_read($AnboxStatus::CMD_ANBOX." check-features");
    my $version = exec_read($AnboxStatus::CMD_ANBOX." version");
    my $container = exec_read($AnboxStatus::CMD_SYSTEMCTL." status ".$AnboxStatus::SERVICE.' | grep "Active:"');
    my $address = exec_read($AnboxStatus::CMD_IFCONFIG.' anbox0 | grep "inet "');


    my $pids = "";
    my $next = "";

    foreach (split(' ', trim(`pidof anbox`))) {
        $pids = $pids.$next.$_.":".trim(`ps -o user= -p $_`);
        $next = " ";
    }



    $AnboxStatus::ip = get_ip($address);
    
    my $ip = $AnboxStatus::ip;
    
    if ($ip eq '') {
        $ip = 'no ip address found';    
    } else {
        $ip = 'anbox '.span_bold($ip);        
    }


    $ui_info_anbox->set_text("$check [$version]");
    $ui_info_container->set_text($container);
    $ui_info_net->set_markup($address.' '.$ip);
    $ui_info_session->set_text("PIDs: $pids");
}



sub get_ip {
    foreach (split(' ', $_[0])) {
      my @ip = split('\.', $_);

      if (@ip == 4) {
         $ip[3] = $ip[3] + 1;
         return "$ip[0].$ip[1].$ip[2].$ip[3]";
      }
    }
    return "";
}


sub exec_read {
    my ($command) = @_;
    my $result = `$command`;
    
    $result //= "";
    $result = trim($result);
    
    if ($result eq "") {
        $result = "ERROR: $command"; 
    }
    return $result;
}


sub trim {
    my ($result) = @_;
    $result =~ s/\n//g;
    $result =~ s/ +/ /g; # double spaces
    $result =~ s/^ //g;  # first space
    $result =~ s/ $//g;  # last space
    return $result
}


sub exec_launch {
    my ( $command, $name ) = @_;
    my $time = get_time();

    system($command);

    if ($? != 0) {
        exec_launch_error($time, $command);
    } else {
        exec_launch_success($time, $command);
    }
}


sub get_time {
    my ($sec,$min,$hour) = localtime(time);
    return sprintf("\@%02d:%02d:%02d",
                    $hour, $min, $sec);
}


sub exec_launch_error {
    my ( $time, $message ) = @_;
    my $status = span_color("ERROR", "red");
    $message = span_bold($message);
    $ui_info_launch->set_markup($time." ".$message." ".$status);
}


sub exec_launch_success {
    my ( $time, $message ) = @_;
    $message = span_bold($message);
    $ui_info_launch->set_markup($time." ".$message);
}


sub span {
    my ($text) = @_;

    $text = encode_entities( $text );
    return "<span>$text</span>"
}

sub span_bold {
    my ($text) = @_;

    $text = encode_entities( $text );
    return "<span><b>$text</b></span>"
}

sub span_color {
    my ($text, $color) = @_;

    $text = encode_entities( $text );
    return "<span foreground=\"$color\">$text</span>"
}



sub read_all_desktop_files {

    @dom_desktops = ();

    foreach ( @AnboxStatus::DESKTOPS ) {
        read_desktop_files($_);
    }

    @dom_desktops = sort { %{$a}{'Name'} cmp %{$b}{'Name'} } @dom_desktops;
}


sub read_desktop_files {
    my $dir = $_[0];

    if (-d $dir) {
        my @files = glob("$dir/*.desktop");

        foreach my $file (@files) {
            read_desktop_file($file);
        }
    }
}


sub read_desktop_file {
    my $file = $_[0];

    if (open my $handle, "<", $file) {
        my %configs;

        while (<$handle>) {
            my @line = split('=', $_,2);
            if (@line == 2) {
               $configs{trim($line[0])} = trim($line[1]);
            }
        }
        close $handle;

        if (%configs > 1) {
            push @dom_desktops, \%configs;
        }
    }
}

Gtk3->main;
