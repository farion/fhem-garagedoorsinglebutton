# $Id$
##############################################################################
#
#     98_GarageDoorSingleButton.pm
#     A FHEM Perl module to handle garage doors with a single button.
#
#     Copyright by Frieder Reinhold
#     e-mail: reinhold@trigon-media.com
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#
# Version: 0.0.6
#
# Version History
#
# - 0.0.6 - 05.10.2017
# Fixed a bug related to BlockingCall
#
# - 0.0.5 - 04.02.2017
# Added openSensorDevice and openSensorDeviceEvent for second sensor that shows
# if door is open.
#
# - 0.0.4 - 06.12.2016
# Fixed some small uninitialized warnings
#
# - 0.0.3 - 02.12.2016
# Fixed some bugs (thx to hartenthaler)
#
# - 0.0.2 - 29.12.2016
# Added buttonTriggerCommand
# Added closeSensorDeviceEvent
# Make use of NotifyFn to get events from close device (thx to marvin78)
#
# - 0.0.1
# Intital Release
#
##############################################################################

package main;

use strict;
use warnings;
use vars qw(%data);
use Time::Local;
use Data::Dumper;

no if $] >= 5.017011, warnings => 'experimental::smartmatch';

sub GarageDoorSingleButton_Set($@);
sub GarageDoorSingleButton_Define($$);
sub GarageDoorSingleButton_Undefine($$);


use constant {
    GarageDoorSingleButton_State_Undefined        => 0,
    GarageDoorSingleButton_State_Open             => 1,
    GarageDoorSingleButton_State_DrivingDown      => 2,
    GarageDoorSingleButton_State_DrivingUp        => 3,
    GarageDoorSingleButton_State_StoppedOnWayDown => 4,
    GarageDoorSingleButton_State_StoppedOnWayUp   => 5,
    GarageDoorSingleButton_State_Closed           => 6
};

###################################
sub GarageDoorSingleButton_Initialize($) {
    my ($hash) = @_;

    Log3 $hash, 5, "[GarageDoorSingleButton] Entering";

    $hash->{SetFn} = "GarageDoorSingleButton_Set";
    $hash->{DefFn} = "GarageDoorSingleButton_Define";
    $hash->{UndefFn} = "GarageDoorSingleButton_Undefine";
    $hash->{AttrFn} = "GarageDoorSingleButton_Attr";
    $hash->{NotifyFn} = "GarageDoorSingleButton_Notify";
    $hash->{AttrList} = "totalTimeDown "
        ."totalTimeUp "
        ."turnTime "
        ."buttonDevice "
        ."buttonTriggerCommand "
        ."closeSensorDevice "
        ."closeSensorDeviceEvent "
        ."openSensorDevice "
        ."openSensorDeviceEvent "        
        ."warnFct "
        ."warnTime "
        ."warnRepeat "
        .$readingFnAttributes;
}


####################################
sub GarageDoorSingleButton_Notify($$)
{
  my ($own_hash, $dev_hash) = @_;
  my $ownName = $own_hash->{NAME};
 
  return "" if(IsDisabled($ownName));
 
  my $devName = $dev_hash->{NAME};
 
  if ( $devName eq $own_hash->{CLOSE_SENSOR_DEVICE} ) {
    my $events = deviceEvents($dev_hash,1);
    return if( !$events );

    my $closeSensorDeviceEvent = AttrVal( $ownName, "closeSensorDeviceEvent", "closed" );
 
    foreach my $event (@{$events}) {
      $event = "" if(!defined($event));
      if ( $event eq $closeSensorDeviceEvent ) {
        fhem("set ".$ownName." forceClose");
        return "";
      }
    }
  } 

  if ( $devName eq $own_hash->{OPEN_SENSOR_DEVICE} ) {
    my $events = deviceEvents($dev_hash,1);
    return if( !$events );

    my $openSensorDeviceEvent = AttrVal( $ownName, "openSensorDeviceEvent", "closed" );
 
    foreach my $event (@{$events}) {
      $event = "" if(!defined($event));
      if ( $event eq $openSensorDeviceEvent ) {
        fhem("set ".$ownName." forceOpen");
        return "";
      }
    }
  }   
}

####################################
sub GarageDoorSingleButton_Attr($@) {
    my ($cmd, $name, $aName, $aVal) = @_;
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
    my $hash = $defs{$name};

    if ($aName eq "buttonDevice") {
        if ($cmd eq "set") {
            $hash->{BUTTON_DEVICE} = $aVal;
        }
    }

    if ($aName eq "closeSensorDevice") {
        if ($cmd eq "set") {
            $hash->{CLOSE_SENSOR_DEVICE} = $aVal;
        }
    }


    if ($aName eq "openSensorDevice") {
        if ($cmd eq "set") {
            $hash->{OPEN_SENSOR_DEVICE} = $aVal;
        }
    }    

    return undef;
}

###################################
sub GarageDoorSingleButton_Define($$) {

    my ( $hash, $def ) = @_;

    my @a = split( "[ \t]+", $def, 5 );

    return "Usage: define <name> GarageDoorSingleButton <buttonDevice> <closeSensorDevice> <openSensorDevice>"
        if ( int(@a) != 4 && int(@a) != 5);

    $hash->{NAME} = $a[0];
    $hash->{BUTTON_DEVICE} = $a[2];
    $hash->{CLOSE_SENSOR_DEVICE} = $a[3];

    if(defined $a[4]){
        $hash->{OPEN_SENSOR_DEVICE} = $a[4];        
    }

    my $name = $hash->{NAME};

    $hash->{helper}{RUNNING_TRIGGER_COUNT} = 0;

    GarageDoorSingleButton_SetStatus($hash,GarageDoorSingleButton_State_Undefined);

    $hash->{helper}{PRESSES_DONE} = 0;
    $hash->{helper}{PRESS_TOTAL} = 0;
    $hash->{helper}{PRESS_QUEUE} = 0;
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "pressQueueSize",$hash->{helper}{PRESS_QUEUE});
    readingsBulkUpdate($hash, "pressesTriggered",$hash->{helper}{PRESS_TOTAL});
    readingsBulkUpdate($hash, "pressesDone",$hash->{helper}{PRESSES_DONE});
    readingsEndUpdate( $hash, 1 );


    GarageDoorSingleButton_SetStatus($hash,GarageDoorSingleButton_State_Closed);
    $hash->{helper}{TO} = AttrVal( $name, "totalTimeUp", "20" );
    $hash->{helper}{TC} = 0;

    return undef;
}

###################################
sub GarageDoorSingleButton_UpdateTimes($) {

    my ( $hash ) = @_;
    my $name = $hash->{NAME};

    my $totalTimeDown = AttrVal( $name, "totalTimeDown", "18" );
    my $totalTimeUp = AttrVal( $name, "totalTimeUp", "20" );

    if ( defined $hash->{helper}{DOORSTATE} && $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_DrivingDown ) {
        $hash->{helper}{TC} = $hash->{helper}{TC} - ( gettimeofday() - $hash->{helper}{LASTTIME} );
        $hash->{helper}{TO} = $totalTimeUp - $totalTimeUp * $hash->{helper}{TC} / $totalTimeDown;
    }elsif ( defined $hash->{helper}{DOORSTATE} && $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_DrivingUp ) {
        $hash->{helper}{TO} = $hash->{helper}{TO} - ( gettimeofday() - $hash->{helper}{LASTTIME} );
        $hash->{helper}{TC} = $totalTimeDown - $totalTimeDown * $hash->{helper}{TO} / $totalTimeUp;
    }
    $hash->{helper}{LASTTIME} = gettimeofday();
    GarageDoorSingleButton_WriteTimes($hash);

}

###################################
sub GarageDoorSingleButton_WriteTimes($) {

    my ( $hash ) = @_;
    my $name = $hash->{NAME};

    if ( defined $hash->{helper}{TC} && defined $hash->{helper}{TO} ) {

        my $totalTimeDown = AttrVal( $name, "totalTimeDown", "20" );
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "timeToClose",sprintf "%.2f", $hash->{helper}{TC});
        readingsBulkUpdate($hash, "timeToOpen",sprintf "%.2f", $hash->{helper}{TO});
        readingsBulkUpdate($hash, "level",sprintf "%.0f",  $hash->{helper}{TC} / $totalTimeDown * 100);
        readingsEndUpdate( $hash, 1 );
    }
}

###################################
sub GarageDoorSingleButton_CheckTimes($) {

    my ( $hash ) = @_;

    GarageDoorSingleButton_UpdateTimes($hash);

    if ( $hash->{helper}{TC} <= 0 && $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_DrivingDown ) {
        GarageDoorSingleButton_SetStatus($hash, GarageDoorSingleButton_State_Closed);
    }elsif ( $hash->{helper}{TO} <= 0 &&  $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_DrivingUp ) {
        GarageDoorSingleButton_SetStatus($hash, GarageDoorSingleButton_State_Open);
    }else {
        InternalTimer(gettimeofday()+1, "GarageDoorSingleButton_CheckTimes", $hash, 0);
    }
    
}

###################################
sub GarageDoorSingleButton_CallWarnFct($){
    my ( $hash ) = @_;    
    my $name = $hash->{NAME};
    my $warnFct = AttrVal( $name, "warnFct", "" );
    my $warnTime = AttrVal( $name, "warnTime", "" );
    my $warnRepeat = AttrVal( $name, "warnRepeat", "1" );

    if( $warnFct && $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_Open ) {
        fhem($warnFct);
        #e.g.: set jabber msg reinhold@trigon-media.com foo
        if (  $warnRepeat == "1") {
            InternalTimer(gettimeofday()+$warnTime, "GarageDoorSingleButton_CallWarnFct", $hash, 0);
        }
    }
}



###################################
sub GarageDoorSingleButton_SetStatus($$) {
    my ( $hash, $state ) = @_;

    if ( defined $hash->{helper}{DOORSTATE} && $state == $hash->{helper}{DOORSTATE} ) {
        return undef;
    }

    GarageDoorSingleButton_UpdateTimes($hash);

    my $name = $hash->{NAME};

    my $totalTimeDown = AttrVal( $name, "totalTimeDown", "18" );
    my $totalTimeUp = AttrVal( $name, "totalTimeUp", "20" );
    my $warnFct = AttrVal( $name, "warnFct", "" );
    my $warnTime = AttrVal( $name, "warnTime", "300" );

    $hash->{helper}{DOORSTATE} = $state;
    $name = $hash->{NAME};

    readingsBeginUpdate($hash);

    if ( $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_Undefined ) {
        
        readingsBulkUpdate($hash, "state","Undefined");
        Log3 $name, 3, "[GarageDoorSingleButton] Change state: Undefined";    
    }
    elsif ( $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_Open ) {
        $hash->{helper}{TC} = $totalTimeDown;
        $hash->{helper}{TO} = 0;
        RemoveInternalTimer($hash);
        readingsBulkUpdate($hash, "state","Open");
        Log3 $name, 3, "[GarageDoorSingleButton] Change state: Open";  
        my $openSensorDeviceEvent = AttrVal( $name, "openSensorDeviceEvent", "closed" );
        my $closeSensorDeviceEvent = AttrVal( $name, "closeSensorDeviceEvent", "closed" );
        if ( fhem("get ".$hash->{CLOSE_SENSOR_DEVICE}." param state") eq $closeSensorDeviceEvent ||
            fhem("get ".$hash->{OPEN_SENSOR_DEVICE}." param state") ne $openSensorDeviceEvent ) {
            readingsBulkUpdate($hash, "inconsistent","Yes");
        }else{
            readingsBulkUpdate($hash, "inconsistent","No");
        }
        if( $warnFct ){  
            InternalTimer(gettimeofday()+$warnTime, "GarageDoorSingleButton_CallWarnFct", $hash, 0);
        }

    }
    elsif ( $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_DrivingDown ) {
        readingsBulkUpdate($hash, "state","DrivingDown");
        Log3 $name, 3, "[GarageDoorSingleButton] Change state: DrivingDown";    
    }
    elsif ( $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_DrivingUp ) {
        readingsBulkUpdate($hash, "state","DrivingUp");
        Log3 $name, 3, "[GarageDoorSingleButton] Change state: DrivingUp";    
    }
    elsif ( $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_StoppedOnWayDown ) {
        readingsBulkUpdate($hash, "state","StoppedOnWayDown");
        Log3 $name, 3, "[GarageDoorSingleButton] Change state: StoppedOnWayDown";    
    }
    elsif ( $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_StoppedOnWayUp ) {
        readingsBulkUpdate($hash, "state","StoppedOnWayUp");
        Log3 $name, 3, "[GarageDoorSingleButton] Change state: StoppedOnWayUp";    
    }
    elsif ( $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_Closed ) {
        $hash->{helper}{TC} = 0;
        $hash->{helper}{TO} = $totalTimeUp;
        RemoveInternalTimer($hash);
        readingsBulkUpdate($hash, "state","Closed");
        Log3 $name, 3, "[GarageDoorSingleButton] Change state: Closed";    

        my $openSensorDeviceEvent = AttrVal( $name, "openSensorDeviceEvent", "closed" );
        my $closeSensorDeviceEvent = AttrVal( $name, "closeSensorDeviceEvent", "closed" );

        if ( fhem("get ".$hash->{CLOSE_SENSOR_DEVICE}." param state") ne $closeSensorDeviceEvent ||
            fhem("get ".$hash->{OPEN_SENSOR_DEVICE}." param state") eq $openSensorDeviceEvent ) {
            readingsBulkUpdate($hash, "inconsistent","Yes");
        }else{
            readingsBulkUpdate($hash, "inconsistent","No");
        }
    }
    readingsEndUpdate( $hash, 1 );
    GarageDoorSingleButton_WriteTimes($hash);
}

###################################
sub GarageDoorSingleButton_UpdateStateByPress($){
    my ( $hash ) = @_;

    if ( $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_Open ) {
        GarageDoorSingleButton_SetStatus($hash,GarageDoorSingleButton_State_DrivingDown);
    }
    elsif ( $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_DrivingDown ) {
        GarageDoorSingleButton_SetStatus($hash,GarageDoorSingleButton_State_StoppedOnWayDown);
    }
    elsif ( $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_DrivingUp ) {
        GarageDoorSingleButton_SetStatus($hash,GarageDoorSingleButton_State_StoppedOnWayUp);
    }
    elsif ( $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_StoppedOnWayDown ) {
        GarageDoorSingleButton_SetStatus($hash,GarageDoorSingleButton_State_DrivingUp);
    }
    elsif ( $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_StoppedOnWayUp ) {
        GarageDoorSingleButton_SetStatus($hash,GarageDoorSingleButton_State_DrivingDown);
    }
    elsif ( $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_Closed ) {
        GarageDoorSingleButton_SetStatus($hash,GarageDoorSingleButton_State_DrivingUp);
    }

    return undef;
}


###################################
sub GarageDoorSingleButton_Open($){
    my ( $hash ) = @_;

    if ( $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_DrivingDown ) {
        return GarageDoorSingleButton_Trigger($hash,2);
    }
    elsif ( $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_StoppedOnWayDown ) {
        return GarageDoorSingleButton_Trigger($hash,1);
    }
    elsif ( $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_StoppedOnWayUp ) {
        return GarageDoorSingleButton_Trigger($hash,3);
    }
    elsif ( $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_Closed ) {
        return GarageDoorSingleButton_Trigger($hash,1);
    }    

    return undef;
}

###################################
sub GarageDoorSingleButton_Close($){
    my ( $hash ) = @_;

    if ( $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_Open ) {
        return GarageDoorSingleButton_Trigger($hash,1);
    }
    elsif ( $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_DrivingUp ) {
        return GarageDoorSingleButton_Trigger($hash,2);
    }
    elsif ( $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_StoppedOnWayDown ) {
        return GarageDoorSingleButton_Trigger($hash,3);
    }
    elsif ( $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_StoppedOnWayUp ) {
        return GarageDoorSingleButton_Trigger($hash,1);
    }
    return undef;    
}

###################################
sub GarageDoorSingleButton_Stop($){
    my ( $hash ) = @_;

    if ( $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_DrivingUp ||
         $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_DrivingDown ) {
        return GarageDoorSingleButton_Trigger($hash,1);
    }
    return undef;    
}

###################################
sub GarageDoorSingleButton_Press($){

    my ( $hash ) = @_;
    
    $hash->{helper}{PRESS_QUEUE} = $hash->{helper}{PRESS_QUEUE}+1;
    $hash->{helper}{PRESS_TOTAL} = $hash->{helper}{PRESS_TOTAL}+1;
    GarageDoorSingleButton_UpdateStateByPress($hash);
    GarageDoorSingleButton_PressTriggerRun($hash);

    return undef;
}

###################################
sub GarageDoorSingleButton_PressTriggerRun($) {

    my ( $hash ) = @_;

    if(!exists($hash->{helper}{RUNNING_PID_PRESS}) && $hash->{helper}{PRESS_QUEUE} > 0) {

        $hash->{helper}{RUNNING_PID_PRESS} = BlockingCall("GarageDoorSingleButton_PressRun", $hash->{NAME},
            "GarageDoorSingleButton_PressDone", 300,
            "GarageDoorSingleButton_PressAborted", $hash);

        my $name = $hash->{NAME};
        my $buttonTriggerCommand = AttrVal( $name, "buttonTriggerCommand", "on-for-timer 1" );

        fhem("set ".$hash->{BUTTON_DEVICE}." ".$buttonTriggerCommand);
        $hash->{helper}{PRESS_QUEUE} = $hash->{helper}{PRESS_QUEUE}-1;
        $hash->{helper}{PRESSES_DONE} = $hash->{helper}{PRESSES_DONE}+1;
    }

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "pressQueueSize",$hash->{helper}{PRESS_QUEUE});
    readingsBulkUpdate($hash, "pressesTriggered",$hash->{helper}{PRESS_TOTAL});
    readingsBulkUpdate($hash, "pressesDone",$hash->{helper}{PRESSES_DONE});
    readingsEndUpdate( $hash, 1 );

    return undef;
}


###################################
sub GarageDoorSingleButton_PressRun($){

    my ($name) = @_;
    my $hash = $defs{$name};

    Log3 $name, 3, "[GarageDoorSingleButton] Init run".$hash->{helper}{PRESS_QUEUE}; 

    sleep 2;

    return $name;
}

###################################
sub GarageDoorSingleButton_PressDone($){

    my ($name) = @_;
    my $hash = $defs{$name};

    delete($hash->{helper}{RUNNING_PID_PRESS});
    GarageDoorSingleButton_PressTriggerRun($hash);
    
}

##########################################
sub GarageDoorSingleButton_PressAborted($)
{
    my ($hash) = @_;
    Log3 $hash->{NAME}, 4, "[GarageDoorSingleButton] Press queue aborted";
    delete($hash->{helper}{RUNNING_PID_PRESS});

    return undef;
}

###################################
sub GarageDoorSingleButton_TriggerUpdateTimer($) {

    my ( $hash ) = @_;
    RemoveInternalTimer($hash);

    if ( $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_DrivingDown || 
         $hash->{helper}{DOORSTATE} == GarageDoorSingleButton_State_DrivingUp ) {
        InternalTimer(gettimeofday()+1, "GarageDoorSingleButton_CheckTimes", $hash, 0);
    } else {
        GarageDoorSingleButton_CheckTimes($hash);
    }
    
    return undef;
}

###################################
sub GarageDoorSingleButton_Trigger($$){
    my ( $hash, $times ) = @_;

    my $i;
    for ($i = 0; $i < $times; $i++) {
        GarageDoorSingleButton_Press($hash);
    }
    GarageDoorSingleButton_TriggerUpdateTimer($hash);


    #if ( $hash->{helper}{RUNNING_TRIGGER_COUNT} > 0 )  {
    #    Log3 $hash, 1, "[GarageDoorSingleButton] Trigger already active.";
    #    return undef;
    #}
    #$hash->{helper}{RUNNING_TRIGGER_COUNT} = $times;

    #GarageDoorSingleButton_DoTrigger($hash);
}

###################################
#sub GarageDoorSingleButton_DoTrigger($){

    #my ( $hash ) = @_;

    #Log3 $hash, 1, "[GarageDoorSingleButton] Trigger do: ".$hash->{helper}{RUNNING_TRIGGER_COUNT} ;

    #if ( $hash->{helper}{RUNNING_TRIGGER_COUNT} > 0 )  {
    #    $hash->{helper}{RUNNING_TRIGGER_COUNT} = $hash->{helper}{RUNNING_TRIGGER_COUNT} -1;
    #    GarageDoorSingleButton_Press($hash);  ##

    #    if ( $hash->{helper}{RUNNING_TRIGGER_COUNT} != 0 ) {
    #        InternalTimer(gettimeofday()+2, "GarageDoorSingleButton_DoTrigger", $hash, 0);
    #    } else { 
    #        GarageDoorSingleButton_TriggerUpdateTimer($hash);
    #    }
    #}

    #return undef;
#}

###################################
sub GarageDoorSingleButton_ForceClose($) {
    my ( $hash ) = @_;
    GarageDoorSingleButton_SetStatus($hash,GarageDoorSingleButton_State_Closed);
}

###################################
sub GarageDoorSingleButton_ForceOpen($) {
    my ( $hash ) = @_;
    GarageDoorSingleButton_SetStatus($hash,GarageDoorSingleButton_State_Open);
}

###################################
sub GarageDoorSingleButton_Undefine($$) {

    my ( $hash, $name ) = @_;

    RemoveInternalTimer($hash);
    BlockingKill($hash->{helper}{RUNNING_PID_PRESS}) if (defined($hash->{helper}{RUNNING_PID_PRESS}));

    return undef;
}

###################################
sub GarageDoorSingleButton_Set($@) {
    my ( $hash, @a ) = @_;
    my $name = $hash->{NAME};
    my $state = $hash->{STATE};

    return "No Argument given" if ( !defined( $a[1] ) );

    my $usage = "Unknown argument ".$a[1].", choose one of open close stop press forceClose forceOpen";

    Log3 $name, 5, "[GarageDoorSingleButton] Called set: ".$a[1];    

    if ($a[1] eq "open") {
        return GarageDoorSingleButton_Open($hash);
    }
    elsif ($a[1] eq "stop") {
        return GarageDoorSingleButton_Stop($hash);
    }
    elsif ($a[1] eq "close") {
        return GarageDoorSingleButton_Close($hash);
    }
    elsif ($a[1] eq "press") {
        return GarageDoorSingleButton_Trigger($hash,1);
    }
    elsif ($a[1] eq "forceClose") {
        return GarageDoorSingleButton_ForceClose($hash);
    }
    elsif ($a[1] eq "forceOpen") {
        return GarageDoorSingleButton_ForceOpen($hash);
    }
    else {
        return $usage;
    }

    return undef;
}

1;

=pod

=begin html

    TODO
    
=end html

=cut
